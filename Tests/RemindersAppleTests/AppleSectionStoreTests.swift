import Foundation
import Synchronization
import Testing

@testable import RemindersApple
@testable import RemindersCore

private let listID = "0C9D8E7F-6A5B-4C3D-8E2F-1A0B9C8D7E6F"
private let dairyID = "1D2E3F4A-5B6C-4D7E-8F9A-0B1C2D3E4F5A"
private let milkID = "2E3F4A5B-6C7D-4E8F-9A0B-1C2D3E4F5A6B"
private let butterID = "3F4A5B6C-7D8E-4F9A-0B1C-2D3E4F5A6B7C"
private let applesID = "4A5B6C7D-8E9F-4A0B-1C2D-3E4F5A6B7C8D"
private let groceries = ReminderList(id: listID, title: "Groceries")

/// ReminderKit as sections and memberships in memory, recording what it was asked to do.
private final class FakeReminderKit: ReminderKitBridge {
  struct State {
    /// In fetch order.
    var sections: [ReminderKitSection] = [ReminderKitSection(id: dairyID, displayName: "Dairy")]
    var storedOrder: [String] = []
    var creationDateSelector: String?
    /// Every reminder in the list's section, as ReminderKit answers per reminder.
    var memberships: [SectionMemberships.Entry] = [.init(reminderID: milkID, sectionID: dairyID)]
    var manualOrder: [String]?
    var calls: [String] = []
    /// The reminder identifiers each membership read asked about; nil for every reminder in the list.
    var membershipQueries: [[String]?] = []
    var failure: RemindersError?
    /// Saves report success but change nothing, as the untracked list change item did on the Mac.
    var dropsWrites = false
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

  func memberships(in list: ReminderList, reminderIDs: [String]?) throws(RemindersError)
    -> ReminderKitRead<[SectionMemberships.Entry]>
  {
    try state.withLock { state throws(RemindersError) in
      if let failure = state.failure { throw failure }
      state.membershipQueries.append(reminderIDs)
      let wanted = reminderIDs.map(Set.init)
      return ReminderKitRead(
        state.memberships.filter { wanted?.contains($0.reminderID) ?? true },
        via: "fetchListSectionWithReminderID:error:")
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

  func deleteSection(id: String, in list: ReminderList, clearing members: [String]) throws(RemindersError) {
    try state.withLock { state throws(RemindersError) in
      if let failure = state.failure { throw failure }
      state.calls.append("delete \(id) in \(list.title), clearing \(members)")
      guard !state.dropsWrites else { return }
      state.sections.removeAll { $0.id == id }
      state.memberships.removeAll { members.contains($0.reminderID) }
    }
  }

  func assign(reminderID: String, toSectionID sectionID: String, in list: ReminderList) throws(RemindersError) {
    try state.withLock { state throws(RemindersError) in
      if let failure = state.failure { throw failure }
      state.calls.append("assign \(reminderID) to \(sectionID) in \(list.title)")
      guard !state.dropsWrites else { return }
      state.memberships.removeAll { $0.reminderID == reminderID }
      state.memberships.append(.init(reminderID: reminderID, sectionID: sectionID))
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
  let reminderKit = FakeReminderKit()
  let log = DiagnosticLog()
  let service: RemindersService
  let store: AppleSectionStore

  init() {
    store = AppleSectionStore(
      reminderKit: reminderKit, diagnostics: { [log] line in log.append(line) }, checkDelays: [.zero, .zero])
    service = RemindersService(
      store: InMemoryReminderStore(
        lists: [groceries],
        reminders: [
          Reminder(id: milkID, title: "Milk", listID: listID, listName: "Groceries"),
          Reminder(id: applesID, title: "Apples", listID: listID, listName: "Groceries"),
        ]),
      sections: store)
  }
}

@Suite("Sections through ReminderKit")
struct AppleSectionStoreTests {
  @Test("reads come from ReminderKit, in the list's stored order, and say so with REMINDERS_DEBUG")
  func reads() async throws {
    let setup = Setup()
    let produce = ReminderKitSection(id: UUID().uuidString, displayName: "Produce")
    setup.reminderKit.state.withLock {
      $0.sections.append(produce)
      $0.storedOrder = [produce.id, dairyID]
      $0.manualOrder = [milkID]
    }
    let sections = try await setup.store.sections(in: groceries)
    #expect(sections.map(\.displayName) == ["Produce", "Dairy"])
    #expect(sections.map(\.sortOrder) == [0, 1])
    #expect(sections.allSatisfy { $0.listName == "Groceries" })
    let memberships = try await setup.store.memberships(of: groceries, reminderIDs: [milkID, applesID])
    #expect(try SectionMemberships(storedData: memberships.data).sectionsByReminder == [milkID: dairyID])
    #expect(await setup.store.manualReminderOrder(of: groceries) == [milkID])
    #expect(setup.reminderKit.state.withLock(\.membershipQueries) == [[milkID, applesID]])
    #expect(
      setup.log.withLock { $0 } == [
        "sections: reminderkit fetchListSectionsInList:error:; order: reminderkit sectionIDsOrderingAsData, "
          + "then fetch order",
        "memberships: reminderkit fetchListSectionWithReminderID:error:",
        "manual order: reminderkit sortingStyle, reminderIDsOrdering",
      ])
  }

  @Test("the service asks only about the reminders it shows, and tags them with their section")
  func listing() async throws {
    let setup = Setup()
    let listing = try await setup.service.sections(ofList: "Groceries")
    #expect(listing.sections.map(\.displayName) == ["Dairy"])
    let queried = try #require(setup.reminderKit.state.withLock(\.membershipQueries).first.flatMap { $0 })
    #expect(Set(queried) == [milkID, applesID])
    let contents = try await setup.service.contents(ofList: "Groceries", section: "Dairy")
    #expect(contents.reminders.map(\.title) == ["Milk"])
  }

  /// The scratch list on the Mac: Alpha, Beta and Gamma created in that order, then arranged Gamma, Alpha, Beta.
  /// ReminderKit fetched them in the arranged order.
  private static let scratchAsFetched = [
    dated("EB33B981-786B-420F-8E73-70512A532667", "Gamma", 3),
    dated("ABCECB2F-5CED-4351-8028-5CE6774B6C9B", "Alpha", 1),
    dated("CE743022-A15F-4347-AA00-877C21C65423", "Beta", 2),
  ]

  /// Grocery on the Mac, in the app's order (newest first); it was never reordered, so nothing is stored.
  /// ReminderKit fetched the sections oldest first, the reverse.
  private static let grocery = [
    dated("F3931B94-08B5-43C1-B332-20E95EEF1CCE", "Personal Care & Health", 4),
    dated("3E6B8719-9921-4B5D-99CA-F11AF351B23B", "Bakery", 3),
    dated("C47A9B40-54DC-4F73-B0F1-A41E545465EE", "Produce", 2),
    dated("356FB2F0-F3E6-4281-A0D1-E22481E481B1", "Breads & Cereals", 1),
  ]

  private static func dated(_ id: String, _ name: String, _ offset: Double) -> ReminderKitSection {
    ReminderKitSection(
      id: id, displayName: name, createdAt: Date(timeIntervalSinceReferenceDate: 780_000_000 + offset))
  }

  private func names(_ sections: [ReminderKitSection], dates: Bool = true) async throws -> [String] {
    let setup = Setup()
    setup.reminderKit.state.withLock {
      $0.sections = sections
      $0.creationDateSelector = dates ? "creationDate" : nil
    }
    return try await setup.store.sections(in: groceries).map(\.displayName)
  }

  @Test("an arranged list keeps ReminderKit's fetch order, which already applies the stored order (scratch list)")
  func arrangedFetchOrder() async throws {
    #expect(try await names(Self.scratchAsFetched) == ["Gamma", "Alpha", "Beta"])
    let setup = Setup()
    setup.reminderKit.state.withLock {
      $0.sections = Self.scratchAsFetched
      $0.creationDateSelector = "creationDate"
    }
    _ = try await setup.store.sections(in: groceries)
    #expect(
      setup.log.withLock { $0.last } == "sections: reminderkit fetchListSectionsInList:error:; order: fetch order")
  }

  @Test("a section added to an arranged list comes back last, and the fetch order is kept (scratch list + Epsilon)")
  func newSectionAppended() async throws {
    let epsilon = Self.dated("5D0C2E8A-3B7F-4C61-9E2D-8A1F4B6C7D90", "Epsilon", 4)
    #expect(try await names(Self.scratchAsFetched + [epsilon]) == ["Gamma", "Alpha", "Beta", "Epsilon"])
  }

  @Test("a fetch order that is oldest first means nothing is stored, so it's reversed to newest first (Grocery)")
  func unarrangedReversed() async throws {
    #expect(try await names(Self.grocery.reversed()) == Self.grocery.map(\.displayName))
    let setup = Setup()
    setup.reminderKit.state.withLock {
      $0.sections = Self.grocery.reversed()
      $0.creationDateSelector = "creationDate"
    }
    _ = try await setup.store.sections(in: groceries)
    #expect(
      setup.log.withLock { $0.last }?.hasSuffix("fetch order reversed (ascending creationDate, so none arranged)")
        == true)
  }

  // The README's known limitation: no ReminderKit getter tells a stored oldest-first order from none at all.
  @Test("a stored order that happens to be oldest first is shown newest first (the documented edge case)")
  func storedOldestFirst() async throws {
    let oldestFirst = Self.scratchAsFetched.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    #expect(try await names(oldestFirst) == ["Gamma", "Beta", "Alpha"])
  }

  @Test("without creation dates, or with one section, the fetch order is kept")
  func fetchOrderKept() async throws {
    #expect(try await names(Self.grocery.reversed(), dates: false) == Self.grocery.reversed().map(\.displayName))
    #expect(try await names([Self.grocery[0]]) == [Self.grocery[0].displayName])
  }

  @Test("a stored order a ReminderKit getter exposes still comes first; sections it doesn't name follow")
  func storedOrderGetter() async throws {
    let setup = Setup()
    setup.reminderKit.state.withLock {
      $0.sections = Self.grocery.reversed()
      $0.creationDateSelector = "creationDate"
      $0.storedOrder = [Self.grocery[2].id]
    }
    #expect(
      try await setup.store.sections(in: groceries).map(\.displayName) == [
        "Produce", "Personal Care & Health", "Bakery", "Breads & Cereals",
      ])
    #expect(
      setup.log.withLock { $0.last }?.contains("order: reminderkit sectionIDsOrderingAsData, then fetch order") == true)
  }

  @Test("when ReminderKit can't answer a read, the error says so; nothing else is read instead")
  func unavailable() async throws {
    let setup = Setup()
    setup.reminderKit.state.withLock {
      $0.failure = .reminderKitUnavailable("REMListSectionsDataView doesn't respond to fetchListSectionWithReminderID")
    }
    do {
      _ = try await setup.store.sections(in: groceries)
      Issue.record("expected an error")
    } catch {
      #expect(error.code == .reminderKitUnavailable)
    }
    await #expect(throws: RemindersError.self) {
      _ = try await setup.store.memberships(of: groceries, reminderIDs: [milkID])
    }
    #expect(await setup.store.manualReminderOrder(of: groceries) == nil)
    // The list itself is still shown, without sections.
    let contents = try await setup.service.contents(ofList: "Groceries")
    #expect(Set(contents.reminders.map(\.title)) == ["Milk", "Apples"])
  }

  @Test("a change that saves without error but isn't there when read back is WRITE_NOT_APPLIED, never success")
  func notApplied() async throws {
    let setup = Setup()
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
    let setup = Setup()
    let frozen = try await setup.service.createSection(named: "Frozen", inList: "groc")
    #expect(frozen.message == "Created section \"Frozen\" in \"Groceries\"")
    let created = setup.reminderKit.state.withLock { $0.sections.last }
    #expect(frozen.id == created?.id)
    let dairy = try await setup.service.createSection(named: "Dairy", inList: "Groceries")
    #expect(dairy.id == dairyID)
    #expect(setup.reminderKit.state.withLock(\.calls) == ["create Frozen in Groceries"])
  }

  @Test("delete-section takes every reminder in the section out of it, completed ones too, in the same save")
  func delete() async throws {
    let setup = Setup()
    let produceID = UUID().uuidString
    setup.reminderKit.state.withLock {
      $0.sections.append(ReminderKitSection(id: produceID, displayName: "Produce"))
      // Butter is completed: not one of the reminders the service lists, but still a member.
      $0.memberships = [
        .init(reminderID: milkID, sectionID: dairyID), .init(reminderID: butterID, sectionID: dairyID.lowercased()),
        .init(reminderID: applesID, sectionID: produceID),
      ]
    }
    let result = try await setup.service.deleteSection(named: "dai", inList: "Groceries")
    #expect(result.message == "Deleted section \"Dairy\" from \"Groceries\"")
    #expect(
      setup.reminderKit.state.withLock(\.calls) == ["delete \(dairyID) in Groceries, clearing \([milkID, butterID])"])
    // Every reminder in the list was asked about, not just the incomplete ones.
    #expect(setup.reminderKit.state.withLock(\.membershipQueries) == [nil])
    // Apples, in another section, is untouched.
    #expect(setup.reminderKit.state.withLock(\.memberships) == [.init(reminderID: applesID, sectionID: produceID)])
  }

  @Test("deleting an empty section clears nothing")
  func deleteEmpty() async throws {
    let setup = Setup()
    setup.reminderKit.state.withLock { $0.memberships = [] }
    _ = try await setup.service.deleteSection(named: "Dairy", inList: "Groceries")
    #expect(setup.reminderKit.state.withLock(\.calls) == ["delete \(dairyID) in Groceries, clearing []"])
  }

  @Test("ReminderKit's errors reach the caller unchanged")
  func failures() async throws {
    let setup = Setup()
    setup.reminderKit.state.withLock { $0.failure = .reminderKitUnavailable("the class REMSaveRequest is missing") }
    do {
      _ = try await setup.service.createSection(named: "Frozen", inList: "Groceries")
      Issue.record("expected an error")
    } catch {
      #expect(error.code == .reminderKitUnavailable)
      #expect(error.message == "ReminderKit can't handle sections on this Mac: the class REMSaveRequest is missing")
      #expect(error.suggestion?.contains("/issues") == true)
    }
    await #expect(throws: RemindersError.self) {
      try await setup.service.deleteSection(named: "Dairy", inList: "Groceries")
    }
  }

  @Test("move hands ReminderKit just the one membership and reads it back")
  func move() async throws {
    let setup = Setup()
    _ = try await setup.store.createSection(named: "Frozen", in: groceries)
    let frozen = try #require(setup.reminderKit.state.withLock { $0.sections.first { $0.displayName == "Frozen" } })
    try await setup.store.assign(
      reminderID: milkID, to: Section(id: frozen.id, displayName: "Frozen", listName: "Groceries", sortOrder: 1),
      in: groceries)
    #expect(setup.reminderKit.state.withLock(\.calls).last == "assign \(milkID) to \(frozen.id) in Groceries")
    #expect(setup.reminderKit.state.withLock(\.membershipQueries).last == [milkID])
    #expect(setup.log.withLock { $0.last } == "write: read back, applied (check 1)")
  }
}
