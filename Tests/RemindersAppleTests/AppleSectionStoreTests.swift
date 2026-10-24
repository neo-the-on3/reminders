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
    var sections: [ReminderKitSection] = [ReminderKitSection(id: dairyID, displayName: "Dairy")]
    var calls: [String] = []
    var failure: RemindersError?
  }

  let state = Mutex(State())

  func sections(in list: ReminderList) throws(RemindersError) -> [ReminderKitSection] {
    try state.withLock { state throws(RemindersError) in
      if let failure = state.failure { throw failure }
      return state.sections
    }
  }

  func createSection(named name: String, in list: ReminderList) throws(RemindersError) -> ReminderKitSection {
    try state.withLock { state throws(RemindersError) in
      if let failure = state.failure { throw failure }
      let section = ReminderKitSection(id: UUID().uuidString, displayName: name)
      state.sections.append(section)
      state.calls.append("create \(name) in \(list.title)")
      return section
    }
  }

  func deleteSection(id: String, in list: ReminderList) throws(RemindersError) {
    try state.withLock { state throws(RemindersError) in
      if let failure = state.failure { throw failure }
      state.sections.removeAll { $0.id == id }
      state.calls.append("delete \(id) in \(list.title)")
    }
  }

  func assign(reminderID: String, toSectionID sectionID: String, in list: ReminderList) throws(RemindersError) {
    try state.withLock { state throws(RemindersError) in
      if let failure = state.failure { throw failure }
      state.calls.append("assign \(reminderID) to \(sectionID) in \(list.title)")
    }
  }
}

private struct Setup {
  /// Owns the database's directory, which goes when it does.
  let builder: Builder
  let path: String
  let reminderKit = FakeReminderKit()
  let service: RemindersService
  let store: AppleSectionStore

  init() throws {
    builder = try Builder()
    path = try builder.database(
      "local",
      """
      INSERT INTO ZREMCDBASELIST VALUES (7, 2, 0, \(Builder.blob(listID)), 'Groceries', \
      \(Builder.blob(utf8: storedData)), NULL, NULL);
      INSERT INTO ZREMCDBASESECTION VALUES (11, 3, 0, 7, \(Builder.blob(dairyID)), 'Dairy', 782000000);
      """)
    store = AppleSectionStore(
      database: DatabaseSectionStore(
        system: DatabaseProbe(files: [path]),
        permissions: PermissionGuidance(host: HostApplication(name: "Terminal", bundlePath: "/Terminal.app"))),
      reminderKit: reminderKit)
    service = RemindersService(
      store: InMemoryReminderStore(
        lists: [groceries],
        reminders: [Reminder(id: milkID, title: "Milk", listID: listID, listName: "Groceries")]),
      sections: store)
  }
}

@Suite("Sections: created and deleted through ReminderKit")
struct AppleSectionStoreTests {
  @Test("reads come from the database, not ReminderKit")
  func reads() async throws {
    let setup = try Setup()
    setup.reminderKit.state.withLock { $0.failure = .reminderKitUnavailable("test") }
    #expect(try await setup.store.sections(in: groceries).map(\.id) == [dairyID])
    #expect(try await setup.store.memberships(of: groceries).data == storedData)
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

  @Test("a section the database doesn't have yet goes after the ones it has")
  func createdBeforeSaved() async throws {
    let setup = try Setup()
    let section = try await setup.store.createSection(named: "Frozen", in: groceries)
    #expect(section.displayName == "Frozen")
    #expect(section.listName == "Groceries")
    #expect(section.sortOrder == 1)
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
    #expect(try Data(contentsOf: URL(filePath: setup.path)) == before)
  }
}
