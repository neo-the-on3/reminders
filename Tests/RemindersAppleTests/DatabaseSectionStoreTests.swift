import Foundation
import Testing

@testable import RemindersApple
@testable import RemindersCore

private typealias Builder = ReminderDatabaseBuilder

private let listID = "A1B2C3D4-E5F6-4711-8899-AABBCCDDEEFF"
private let dairyID = "2F1C9A0E-6B7D-4E21-9C35-0A8B7D6E5F41"
private let produceID = "8D4E2B1A-3C5F-4A60-B7E9-1F2D3C4B5A69"
private let milkID = "5A0B1C2D-3E4F-4A5B-8C6D-7E8F9A0B1C2D"
private let breadID = "6B1C2D3E-4F5A-4B6C-9D7E-8F9A0B1C2D3E"
private let storedData =
  #"{"minimumSupportedVersion":20230430,"memberships":[{"memberID":"\#(milkID)","groupID":"\#(dairyID)","modifiedOn":782900000.123456}]}"#
private let storedTokenMap = #"{"map":{"membershipsOfRemindersInSectionsChecksum":{"counter":3}}}"#
private let storedChecksum = SectionMemberships.checksum(of: storedData)

private let groceries = ReminderList(id: listID, title: "Groceries")

/// One account's database: Groceries with Dairy, Produce and a deleted section, plus a deleted list.
private func groceriesSQL() -> String {
  """
  INSERT INTO ZREMCDBASELIST VALUES (7, 2, 0, \(Builder.blob(listID)), 'Groceries', \
  \(Builder.blob(utf8: storedData)), \(Builder.text(storedChecksum)), \(Builder.blob(utf8: storedTokenMap)));
  INSERT INTO ZREMCDBASELIST VALUES (8, 2, 1, \(Builder.blob(UUID().uuidString)), 'Groceries', NULL, NULL, NULL);
  INSERT INTO ZREMCDBASESECTION VALUES (12, 3, 0, 7, \(Builder.blob(produceID)), 'Produce', 783000000);
  INSERT INTO ZREMCDBASESECTION VALUES (11, 3, 0, 7, \(Builder.blob(dairyID)), 'Dairy', 782000000);
  INSERT INTO ZREMCDBASESECTION VALUES (13, 3, 1, 7, \(Builder.blob(UUID().uuidString)), 'Old', 781000000);
  INSERT INTO ZREMCDBASESECTION VALUES (14, 3, 0, 8, \(Builder.blob(UUID().uuidString)), 'Other list', 781000000);
  """
}

private func store(_ files: [String], fullDiskAccess: Bool = true) -> any SectionStore {
  DatabaseSectionStore(
    system: DatabaseProbe(files: files, fullDiskAccess: fullDiskAccess),
    permissions: PermissionGuidance(host: HostApplication(name: "Terminal", bundlePath: "/Terminal.app")))
}

private func code(_ body: () async throws -> Void) async -> RemindersError.Code? {
  do {
    try await body()
    return nil
  } catch let error as RemindersError {
    return error.code
  } catch {
    return .unknown
  }
}

@Suite("Sections: reading the Reminders database")
struct DatabaseSectionStoreTests {
  @Test("a list's live sections are read in creation order with dashed identifiers")
  func sections() async throws {
    let builder = try Builder()
    let path = try builder.database("local", groceriesSQL())
    let sections = try await store([path]).sections(in: groceries)
    #expect(sections.map(\.displayName) == ["Dairy", "Produce"])
    #expect(sections.map(\.id) == [dairyID, produceID])
    #expect(sections.map(\.sortOrder) == [0, 1])
    #expect(sections.allSatisfy { $0.listName == "Groceries" })
  }

  @Test("membership data, checksum and token map come back exactly as stored")
  func memberships() async throws {
    let builder = try Builder()
    let path = try builder.database("local", groceriesSQL())
    let stored = try await store([path]).memberships(of: groceries)
    #expect(stored == StoredMemberships(data: storedData, checksum: storedChecksum, tokenMap: storedTokenMap))
    #expect(!SectionMemberships.isCorrupt(stored))
  }

  @Test("a list without section data has none")
  func empty() async throws {
    let builder = try Builder()
    let path = try builder.database(
      "local", "INSERT INTO ZREMCDBASELIST VALUES (1, 2, 0, \(Builder.blob(listID)), 'Groceries', NULL, NULL, NULL);")
    #expect(try await store([path]).sections(in: groceries).isEmpty)
    #expect(try await store([path]).memberships(of: groceries) == StoredMemberships())
  }

  @Test("each account's database is searched, by identifier and then by unique name")
  func accounts() async throws {
    let builder = try Builder()
    let other = try builder.database(
      "a-other",
      "INSERT INTO ZREMCDBASELIST VALUES (1, 2, 0, \(Builder.blob(UUID().uuidString)), 'Work', NULL, NULL, NULL);")
    let notReminders = try builder.database("b-unrelated", schema: false, "CREATE TABLE T (X);")
    let icloud = try builder.database("c-icloud", groceriesSQL())
    let files = [other, notReminders, icloud]
    #expect(try await store(files).sections(in: groceries).count == 2)
    let byName = ReminderList(id: "EVENTKIT-ID-THAT-DIFFERS", title: "Groceries")
    #expect(try await store(files).sections(in: byName).count == 2)
    let missing = ReminderList(id: "NOPE", title: "Garden")
    #expect(await code { _ = try await store(files).sections(in: missing) } == .listNotFound)
  }

  @Test("without Full Disk Access the error names the app and the setting")
  func fullDiskAccess() async throws {
    do {
      _ = try await store([], fullDiskAccess: false).sections(in: groceries)
      Issue.record("expected an error")
    } catch {
      #expect(error.code == .permissionDenied)
      #expect(error.message.contains("Full Disk Access for Terminal"))
      #expect(error.suggestion?.contains("Privacy & Security > Full Disk Access") == true)
    }
  }

  @Test("changes are refused and the database is never written")
  func readOnly() async throws {
    let builder = try Builder()
    let path = try builder.database("local", groceriesSQL())
    let before = try Data(contentsOf: URL(filePath: path))
    let sections = store([path])
    let dairy = try await sections.sections(in: groceries)[0]
    #expect(await code { _ = try await sections.createSection(named: "Frozen", in: groceries) } == .notImplemented)
    #expect(await code { try await sections.deleteSection(dairy, in: groceries) } == .notImplemented)
    #expect(
      await code {
        try await sections.replaceMemberships(of: groceries, with: StoredMemberships(), ifUnchangedFrom: .init())
      } == .notImplemented)
    #expect(try Data(contentsOf: URL(filePath: path)) == before)
    #expect(!FileManager.default.fileExists(atPath: path + "-journal"))
  }

  @Test("the connection itself can't write")
  func connectionIsReadOnly() throws {
    let builder = try Builder()
    let path = try builder.database("local", groceriesSQL())
    let database = try SQLiteDatabase(readOnlyAt: path)
    #expect(throws: RemindersError.self) { try database.rows("DELETE FROM ZREMCDBASESECTION") }
    #expect(try database.rows("SELECT count(*) FROM ZREMCDBASESECTION").first?.first == .integer(4))
  }

  @Test("the service lists and filters by sections from the database")
  func service() async throws {
    let builder = try Builder()
    let path = try builder.database("local", groceriesSQL())
    let reminders = [
      Reminder(id: milkID, title: "Milk", listID: listID, listName: "Groceries"),
      Reminder(id: breadID, title: "Bread", listID: listID, listName: "Groceries"),
    ]
    let service = RemindersService(
      store: InMemoryReminderStore(lists: [groceries], reminders: reminders), sections: store([path]))
    let listing = try await service.sections(ofList: "groc")
    #expect(listing.counts == ["Dairy": 1, "Produce": 0])
    let dairy = try await service.contents(ofList: "Groceries", section: "dairy")
    #expect(dairy.reminders.map(\.title) == ["Milk"])
    #expect(dairy.reminders.first?.section == "Dairy")
  }

  @Test("sections follow the list's arranged order; a NULL or unreadable order falls back to creation order")
  func arrangedOrder() async throws {
    func sections(ordering: String) async throws -> [Section] {
      let builder = try Builder()
      let sql =
        groceriesSQL() + """
          ALTER TABLE ZREMCDBASELIST ADD COLUMN ZSECTIONIDSORDERINGASDATA BLOB;
          UPDATE ZREMCDBASELIST SET ZSECTIONIDSORDERINGASDATA = \(ordering) WHERE Z_PK = 7;
          """
      return try await store([try builder.database("local", sql)]).sections(in: groceries)
    }
    let arranged = Builder.blob(
      utf8: #"{"orderedIdentifiers":["\#(produceID)","\#(dairyID)"],"minimumSupportedVersion":20230430}"#)
    let produceFirst = try await sections(ordering: arranged)
    #expect(produceFirst.map(\.displayName) == ["Produce", "Dairy"])
    #expect(produceFirst.map(\.sortOrder) == [0, 1])
    #expect(try await sections(ordering: "NULL").map(\.displayName) == ["Dairy", "Produce"])
    #expect(try await sections(ordering: Builder.blob(utf8: "{")).map(\.displayName) == ["Dairy", "Produce"])
    #expect(try await sections(ordering: "'not json'").map(\.displayName) == ["Dairy", "Produce"])
  }
}
