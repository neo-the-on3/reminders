import Foundation
import Synchronization
import Testing

@testable import RemindersApple
@testable import RemindersCore

private typealias Builder = ReminderDatabaseBuilder

private let listID = "0C9D8E7F-6A5B-4C3D-8E2F-1A0B9C8D7E6F"
private let dairyID = "1D2E3F4A-5B6C-4D7E-8F9A-0B1C2D3E4F5A"
private let milkID = "2E3F4A5B-6C7D-4E8F-9A0B-1C2D3E4F5A6B"
private let storedData =
  #"{"minimumSupportedVersion":20230430,"memberships":[{"memberID":"\#(milkID)","groupID":"\#(dairyID)","modifiedOn":1}]}"#
private let groceries = ReminderList(id: listID, title: "Groceries")

/// ReminderKit as a list of sections in memory, recording what it was asked to do.
private final class FakeReminderKit: ReminderKitBridge {
  struct State {
    /// In fetch order.
    var sections: [ReminderKitSection] = [ReminderKitSection(id: dairyID, displayName: "Dairy")]
    var storedOrder: [String] = []
    var creationDateSelector: String?
    var memberships: StoredMemberships?
    var manualOrder: [String]?
    var calls: [String] = []
    var failure: RemindersError?
    /// Saves report success but change nothing, as the untracked list change item did on the Mac.
    var dropsWrites = false
    /// What the last assignment was handed as the list's current memberships.
    var kept: [SectionMemberships.Entry] = []
  }

  let state = Mutex(State())

  func sections(in list: ReminderList) throws(RemindersError) -> ReminderKitSections {
    try state.withLock { state throws(RemindersError) in
      if let failure = state.failure { throw failure }
      return ReminderKitSections(
        sections: state.sections, storedOrder: state.storedOrder,
        storedOrderSelector: state.storedOrder.isEmpty ? nil : "sectionIDsOrderingAsData",
        creationDateSelector: state.creationDateSelector)
    }
  }

  func memberships(in list: ReminderList) throws(RemindersError) -> ReminderKitRead<StoredMemberships>? {
    try state.withLock { state throws(RemindersError) in
      if let failure = state.failure { throw failure }
      return state.memberships.map { ReminderKitRead($0, via: "membershipsOfRemindersInSectionsAsData") }
    }
  }

  func manualReminderOrder(in list: ReminderList) throws(RemindersError) -> ReminderKitRead<[String]?>? {
    try state.withLock { state throws(RemindersError) in
      if let failure = state.failure { throw failure }
      return state.manualOrder.map { ReminderKitRead($0, via: "sortingStyle, reminderIDsOrdering") }
    }
  }

  func createSection(named name: String, in list: ReminderList) throws(RemindersError) -> ReminderKitSection {
    try state.withLock { state throws(RemindersError) in
      if let failure = state.failure { throw failure }
      let section = ReminderKitSection(id: UUID().uuidString, displayName: name)
      if !state.dropsWrites { state.sections.append(section) }
      state.calls.append("create \(name) in \(list.title)")
      return section
    }
  }

  func deleteSection(id: String, in list: ReminderList) throws(RemindersError) {
    try state.withLock { state throws(RemindersError) in
      if let failure = state.failure { throw failure }
      if !state.dropsWrites { state.sections.removeAll { $0.id == id } }
      state.calls.append("delete \(id) in \(list.title)")
    }
  }

  func assign(
    reminderID: String, toSectionID sectionID: String, in list: ReminderList,
    keeping existing: [SectionMemberships.Entry]
  ) throws(RemindersError) {
    try state.withLock { state throws(RemindersError) in
      if let failure = state.failure { throw failure }
      state.calls.append("assign \(reminderID) to \(sectionID) in \(list.title)")
      state.kept = existing
      guard !state.dropsWrites else { return }
      state.memberships = StoredMemberships(
        entries: existing.filter { $0.reminderID != reminderID } + [.init(reminderID: reminderID, sectionID: sectionID)]
      )
    }
  }
}

/// The diagnostic lines a store printed.
private final class DiagnosticLog: Sendable {
  private let lines = Mutex<[String]>([])
  func append(_ line: String) { lines.withLock { $0.append(line) } }
  func withLock<T>(_ body: ([String]) -> T) -> T { lines.withLock { body($0) } }
}

private struct Setup {
  /// Owns the database's directory, which goes when it does.
  let builder: Builder
  let path: String
  let reminderKit = FakeReminderKit()
  let log = DiagnosticLog()
  let service: RemindersService
  let store: AppleSectionStore

  /// - Parameters:
  ///   - moreSections: Sections after Dairy in the database, in creation order (`Z_PK`).
  ///   - readableDatabase: False for a Mac without Full Disk Access, where the database can't be read.
  init(
    readsThroughReminderKit: Bool = true, moreSections: [ReminderKitSection] = [], readableDatabase: Bool = true
  ) throws {
    builder = try Builder()
    let sectionRows = moreSections.enumerated().map { offset, section in
      "INSERT INTO ZREMCDBASESECTION VALUES (\(12 + offset), 3, 0, 7, \(Builder.blob(section.id)), "
        + "'\(section.displayName)', 782000000);"
    }.joined(separator: "\n")
    path = try builder.database(
      "local",
      """
      INSERT INTO ZREMCDBASELIST VALUES (7, 2, 0, \(Builder.blob(listID)), 'Groceries', \
      \(Builder.blob(utf8: storedData)), NULL, NULL);
      INSERT INTO ZREMCDBASESECTION VALUES (11, 3, 0, 7, \(Builder.blob(dairyID)), 'Dairy', 782000000);
      \(sectionRows)
      """)
    store = AppleSectionStore(
      database: DatabaseSectionStore(
        system: DatabaseProbe(files: readableDatabase ? [path] : []),
        permissions: PermissionGuidance(host: HostApplication(name: "Terminal", bundlePath: "/Terminal.app"))),
      reminderKit: reminderKit, readsThroughReminderKit: readsThroughReminderKit,
      diagnostics: { [log] line in log.append(line) }, checkDelays: [.zero, .zero])
    service = RemindersService(
      store: InMemoryReminderStore(
        lists: [groceries],
        reminders: [Reminder(id: milkID, title: "Milk", listID: listID, listName: "Groceries")]),
      sections: store)
  }
}

@Suite("Sections through ReminderKit")
struct AppleSectionStoreTests {
  @Test("reads come from ReminderKit, in the list's stored order, and say so with REMINDERS_DEBUG")
  func reads() async throws {
    let setup = try Setup()
    let produce = ReminderKitSection(id: UUID().uuidString, displayName: "Produce")
    let fromReminderKit = #"{"memberships":[]}"#
    setup.reminderKit.state.withLock {
      $0.sections.append(produce)
      $0.storedOrder = [produce.id, dairyID]
      $0.memberships = StoredMemberships(data: fromReminderKit)
      $0.manualOrder = [milkID]
    }
    let sections = try await setup.store.sections(in: groceries)
    #expect(sections.map(\.displayName) == ["Produce", "Dairy"])
    #expect(sections.map(\.sortOrder) == [0, 1])
    #expect(sections.allSatisfy { $0.listName == "Groceries" })
    #expect(try await setup.store.memberships(of: groceries).data == fromReminderKit)
    #expect(await setup.store.manualReminderOrder(of: groceries) == [milkID])
    #expect(
      setup.log.withLock { $0 } == [
        "sections: reminderkit fetchListSectionsInList:error:; order: sectionIDsOrderingAsData",
        "memberships: reminderkit membershipsOfRemindersInSectionsAsData",
        "manual order: reminderkit sortingStyle, reminderIDsOrdering",
      ])
  }

  /// Grocery on the Mac: no stored order (NULL), and ReminderKit fetched the sections newest first.
  private static let grocery = ["Personal Care & Health", "Bakery", "Produce", "Breads & Cereals"].map {
    ReminderKitSection(id: UUID().uuidString, displayName: $0)
  }

  @Test("without a stored order, sections go in creation order by ReminderKit's creation dates")
  func creationDates() async throws {
    let setup = try Setup(readableDatabase: false)
    setup.reminderKit.state.withLock {
      $0.sections = Self.grocery.enumerated().reversed().map { offset, section in
        var dated = section
        dated.createdAt = Date(timeIntervalSinceReferenceDate: 780_000_000 + Double(offset))
        return dated
      }
      $0.creationDateSelector = "creationDate"
    }
    let names = try await setup.store.sections(in: groceries).map(\.displayName)
    #expect(names == Self.grocery.map(\.displayName))
    #expect(
      setup.log.withLock { $0.last }
        == "sections: reminderkit fetchListSectionsInList:error:; order: none, then creation date (creationDate)")
  }

  @Test("without a stored order or creation dates, sections follow the database's creation order")
  func databaseCreationOrder() async throws {
    let setup = try Setup(moreSections: Self.grocery)
    setup.reminderKit.state.withLock {
      $0.sections = Self.grocery.reversed() + [ReminderKitSection(id: dairyID, displayName: "Dairy")]
    }
    let names = try await setup.store.sections(in: groceries).map(\.displayName)
    #expect(names == ["Dairy"] + Self.grocery.map(\.displayName))
    #expect(setup.log.withLock { $0.last }?.hasSuffix("order: none, then database order (Z_PK)") == true)
  }

  @Test("with nothing else to go on, sections are in reverse fetch order, as ReminderKit fetches newest first")
  func reversedFetchOrder() async throws {
    let setup = try Setup(readableDatabase: false)
    setup.reminderKit.state.withLock { $0.sections = Self.grocery.reversed() }
    let names = try await setup.store.sections(in: groceries).map(\.displayName)
    #expect(names == Self.grocery.map(\.displayName))
    #expect(setup.log.withLock { $0.last }?.hasSuffix("order: none, then reversed fetch order") == true)
  }

  @Test("sections the stored order doesn't name follow it in creation order")
  func partlyStoredOrder() async throws {
    let setup = try Setup(readableDatabase: false)
    setup.reminderKit.state.withLock {
      $0.sections = Self.grocery.reversed()
      $0.storedOrder = [Self.grocery[2].id]
    }
    let names = try await setup.store.sections(in: groceries).map(\.displayName)
    #expect(names == ["Produce", "Personal Care & Health", "Bakery", "Breads & Cereals"])
  }

  @Test("reads fall back to the database when ReminderKit can't answer, and say why")
  func fallback() async throws {
    let setup = try Setup()
    // ReminderKit without the memberships: they come from the database.
    #expect(try await setup.store.memberships(of: groceries).data == storedData)
    setup.reminderKit.state.withLock { $0.failure = .reminderKitUnavailable("test") }
    #expect(try await setup.store.sections(in: groceries).map(\.id) == [dairyID])
    #expect(try await setup.store.memberships(of: groceries).data == storedData)
    #expect(await setup.store.manualReminderOrder(of: groceries) == nil)
    let log = setup.log.withLock { $0 }
    #expect(
      log.prefix(3) == [
        "memberships: reminderkit exposes no getter", "memberships: database",
        "sections: reminderkit failed (REMINDERKIT_UNAVAILABLE: ReminderKit can't change sections on this Mac: test)",
      ])
    #expect(log.contains("sections: database"))
    #expect(log.last == "manual order: none")
  }

  @Test("with ReminderKit reads off, everything is read from the database")
  func databaseOnly() async throws {
    let setup = try Setup(readsThroughReminderKit: false)
    setup.reminderKit.state.withLock {
      $0.sections = []
      $0.memberships = StoredMemberships(data: "{}")
      $0.manualOrder = [milkID]
    }
    #expect(try await setup.store.sections(in: groceries).map(\.id) == [dairyID])
    #expect(try await setup.store.memberships(of: groceries).data == storedData)
    #expect(await setup.store.manualReminderOrder(of: groceries) == nil)
    #expect(setup.log.withLock { $0.first } == "sections: reminderkit off (REMINDERS_SECTIONS_FROM_DATABASE=1)")
  }

  @Test("a change that saves without error but isn't there when read back is WRITE_NOT_APPLIED, never success")
  func notApplied() async throws {
    let setup = try Setup()
    setup.reminderKit.state.withLock { $0.dropsWrites = true }
    let dairy = Section(id: dairyID, displayName: "Dairy", listName: "Groceries", sortOrder: 0)
    let produce = ReminderKitSection(id: UUID().uuidString, displayName: "Produce")
    setup.reminderKit.state.withLock { $0.sections.append(produce) }
    let target = Section(id: produce.id, displayName: "Produce", listName: "Groceries", sortOrder: 1)
    await #expect(throws: RemindersError.writeNotApplied("the reminder isn't in section \"Produce\" after saving")) {
      try await setup.store.assign(reminderID: milkID, to: target, in: groceries)
    }
    await #expect(throws: RemindersError.self) {
      _ = try await setup.store.createSection(named: "Frozen", in: groceries)
    }
    await #expect(throws: RemindersError.self) { try await setup.store.deleteSection(dairy, in: groceries) }
    do {
      _ = try await setup.service.move(ReminderReference(list: "Groceries", title: "Milk"), toSection: "Produce")
      Issue.record("expected an error")
    } catch {
      #expect(error.code == .writeNotApplied)
    }
    // Every write was read back the first time and after each wait.
    #expect(
      setup.log.withLock { $0.filter { $0.hasPrefix("write: read back, NOT applied after 3 checks") }.count } == 4)
  }

  @Test("create-section asks ReminderKit, and reuses a section with exactly that name")
  func create() async throws {
    let setup = try Setup()
    let frozen = try await setup.service.createSection(named: "Frozen", inList: "groc")
    #expect(frozen.message == "Created section \"Frozen\" in \"Groceries\"")
    let created = setup.reminderKit.state.withLock { $0.sections.last }
    #expect(frozen.id == created?.id)
    let dairy = try await setup.service.createSection(named: "Dairy", inList: "Groceries")
    #expect(dairy.id == dairyID)
    #expect(setup.reminderKit.state.withLock(\.calls) == ["create Frozen in Groceries"])
  }

  @Test("delete-section asks ReminderKit and leaves the database alone")
  func delete() async throws {
    let setup = try Setup()
    let before = try Data(contentsOf: URL(filePath: setup.path))
    let result = try await setup.service.deleteSection(named: "dai", inList: "Groceries")
    #expect(result.message == "Deleted section \"Dairy\" from \"Groceries\"")
    #expect(setup.reminderKit.state.withLock(\.calls) == ["delete \(dairyID) in Groceries"])
    #expect(try Data(contentsOf: URL(filePath: setup.path)) == before)
  }

  @Test("ReminderKit's errors reach the caller unchanged")
  func failures() async throws {
    let setup = try Setup()
    setup.reminderKit.state.withLock { $0.failure = .reminderKitUnavailable("the class REMSaveRequest is missing") }
    do {
      _ = try await setup.service.createSection(named: "Frozen", inList: "Groceries")
      Issue.record("expected an error")
    } catch {
      #expect(error.code == .reminderKitUnavailable)
      #expect(error.message == "ReminderKit can't change sections on this Mac: the class REMSaveRequest is missing")
      #expect(error.suggestion?.contains("Sections can still be listed") == true)
    }
    await #expect(throws: RemindersError.self) {
      try await setup.service.deleteSection(named: "Dairy", inList: "Groceries")
    }
    #expect(try await setup.service.sections(ofList: "Groceries").sections.map(\.displayName) == ["Dairy"])
  }

  @Test("move asks ReminderKit to assign the reminder and leaves the database alone")
  func move() async throws {
    let setup = try Setup()
    let before = try Data(contentsOf: URL(filePath: setup.path))
    _ = try await setup.store.createSection(named: "Frozen", in: groceries)
    let frozen = try #require(setup.reminderKit.state.withLock { $0.sections.first { $0.displayName == "Frozen" } })
    try await setup.store.assign(
      reminderID: milkID, to: Section(id: frozen.id, displayName: "Frozen", listName: "Groceries", sortOrder: 1),
      in: groceries)
    #expect(setup.reminderKit.state.withLock(\.calls).last == "assign \(milkID) to \(frozen.id) in Groceries")
    // The list's current memberships went with the change, and the move was read back.
    #expect(setup.reminderKit.state.withLock(\.kept) == [.init(reminderID: milkID, sectionID: dairyID, modifiedOn: 1)])
    #expect(setup.log.withLock { $0.last } == "write: read back, applied (check 1)")
    #expect(try Data(contentsOf: URL(filePath: setup.path)) == before)
  }
}
