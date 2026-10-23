// Command behaviour against the in-memory store, mirroring remi's src/cli/commands/*.ts.

import Foundation
import Testing

@testable import RemiCore

@Suite("Reminder queries")
struct QueryTests {
  @Test("lists are sorted by title with incomplete and overdue counts (due today counts as overdue)")
  func listCounts() async throws {
    let h = Harness(lists: ["Work", "Groceries", "Empty"])
    h.store.addItem("Milk", list: "Groceries", due: "2026-10-23")
    h.store.addItem("Eggs", list: "Groceries", due: "2026-10-20")
    h.store.addItem("Bread", list: "Groceries", due: "2026-10-24")
    h.store.addItem("Old", list: "Groceries", due: "2026-10-01", completed: true)
    h.store.addItem("Report", list: "Work")
    let lists = try await h.context.listLists()
    #expect(lists.map(\.title) == ["Empty", "Groceries", "Work"])
    #expect(lists.map(\.reminderCount) == [0, 3, 1])
    #expect(lists.map(\.overdueCount) == [0, 2, 0])
  }

  @Test("date filters follow remi's helper")
  func filters() async throws {
    let h = Harness()
    for (title, due) in [
      ("past", "2026-10-01"), ("yesterday", "2026-10-22"), ("today", "2026-10-23"), ("tomorrow", "2026-10-24"),
      ("in7", "2026-10-30"), ("in8", "2026-10-31"), ("far", "2027-01-01"),
    ] {
      h.store.addItem(title, list: "Work", due: due)
    }
    h.store.addItem("undated", list: "Work")
    h.store.addItem("done", list: "Work", due: "2026-10-23", completed: true)
    func titles(_ filter: ReminderFilter) async throws -> [String] {
      try await h.context.getReminders(listID: nil, filter: filter).map(\.title)
    }
    #expect(try await titles(.today) == ["today"])
    #expect(try await titles(.tomorrow) == ["tomorrow"])
    #expect(try await titles(.overdue) == ["past", "yesterday"])
    #expect(try await titles(.upcoming(days: 7)) == ["past", "yesterday", "today", "tomorrow", "in7"])
    #expect(try await titles(.week) == ["past", "yesterday", "today", "tomorrow", "in7"])
    #expect(try await titles(.upcoming(days: 1)) == ["past", "yesterday", "today", "tomorrow"])
    #expect(try await titles(.on(DueDay(year: 2026, month: 10, day: 31))) == ["in8"])
    #expect(try await titles(.incomplete).count == 8)
    #expect(try await titles(.completed) == ["done"])
    #expect(try await titles(.all).last == "done")
  }

  @Test("search matches title or notes, case-insensitively, incomplete only")
  func search() async throws {
    let h = Harness()
    h.store.addItem("Buy MILK", list: "Groceries")
    h.store.addItem("Call", list: "Work", notes: "about the milk run")
    h.store.addItem("milk done", list: "Groceries", completed: true)
    #expect(try await h.context.searchReminders("milk").map(\.title) == ["Buy MILK", "Call"])
  }

  @Test("every operation asks for access and maps refusal to PERMISSION_DENIED")
  func permissionDenied() async throws {
    let h = Harness()
    h.store.access = .denied
    let error = await #expect(throws: RemiCommandError.self) { try await h.context.lists() }
    #expect(error?.code == .permissionDenied)
    #expect(error?.message == "Reminders access not granted")
    #expect(error?.suggestion == "Run: remi authorize (then check System Settings > Privacy & Security > Reminders)")
  }

  @Test("EventKit priority mapping and recurrence descriptions")
  func mappings() {
    #expect(
      (0...9).map { priority(fromEventKit: $0) } == [
        .none, .high, .high, .high, .high, .medium, .low, .low, .low, .low,
      ])
    #expect(
      Priority.allCases.map(eventKitPriority)
        == Priority.allCases.map { ["high": 1, "medium": 5, "low": 9, "none": 0][$0.rawValue]! })
    #expect(describeRecurrence(frequency: .daily, interval: 1, daysOfWeek: []) == "daily")
    #expect(describeRecurrence(frequency: .weekly, interval: 1, daysOfWeek: []) == "weekly")
    #expect(describeRecurrence(frequency: .monthly, interval: 3, daysOfWeek: []) == "every 3 months")
    #expect(describeRecurrence(frequency: .yearly, interval: 1, daysOfWeek: []) == "yearly")
    #expect(describeRecurrence(frequency: .weekly, interval: 2, daysOfWeek: [2, 6]) == "every 2 weeks on Mon, Fri")
    #expect(describeRecurrence(frequency: .daily, interval: 1, daysOfWeek: [2]) == "daily")
  }

  @Test("DueDay parses real calendar dates only")
  func dueDay() {
    #expect(DueDay("2028-02-29")?.string == "2028-02-29")
    #expect(DueDay("2026-02-29") == nil)
    #expect(DueDay("2026-13-01") == nil)
    #expect(DueDay("2026-1-01") == nil)
  }

  @Test("parseInt like JavaScript")
  func parseInt() {
    #expect(jsParseInt("14") == 14)
    #expect(jsParseInt(" 3days") == 3)
    #expect(jsParseInt("-2") == -2)
    #expect(jsParseInt("abc") == nil)
    #expect(jsParseInt("") == nil)
  }
}

@Suite("Reminder commands")
struct CommandTests {
  @Test("view commands print remi's headers")
  func views() async throws {
    let h = Harness()
    h.store.addItem("Milk", list: "Groceries", due: "2026-10-23")
    try await h.context.today()
    try await h.context.overdue()
    try await h.context.upcoming(days: "3")
    try await h.context.upcoming(days: "soon")
    try await h.context.search("mil")
    let text = h.stdout.text
    for header in ["Due Today", "Overdue", "Due in next 3 days", "Due in next NaN days", "Search: \"mil\""] {
      #expect(text.contains(header), "missing \(header)")
    }
  }

  @Test("list resolves names fuzzily and hides completed reminders unless asked")
  func list() async throws {
    let h = Harness(json: true)
    h.store.addItem("Milk", list: "Groceries")
    h.store.addItem("Eggs", list: "Groceries", completed: true)
    try await h.context.list("groc", includeCompleted: false)
    #expect(h.jsonData?.arrayValue?.count == 1)
    let h2 = Harness(json: true)
    h2.store.addItem("Milk", list: "Groceries")
    h2.store.addItem("Eggs", list: "Groceries", completed: true)
    try await h2.context.list("Groceries", includeCompleted: true)
    #expect(h2.jsonData?.arrayValue?.count == 2)
    let error = await #expect(throws: RemiCommandError.self) {
      try await h.context.list("Nope", includeCompleted: false)
    }
    #expect(error?.code == .listNotFound)
  }

  @Test("add creates the reminder and reports its id")
  func add() async throws {
    let h = Harness(json: true)
    try await h.context.add(
      list: "work", title: "Ship it", due: "tomorrow", priority: "high", notes: "n", repeat: "weekly")
    let item = try #require(h.store.item(titled: "Ship it"))
    #expect(item.dueDate == "2026-10-24")
    #expect(item.priority == .high)
    #expect(item.notes == "n")
    #expect(item.recurrence == "weekly")
    #expect(item.listName == "Work")
    #expect(h.jsonData?["message"]?.stringValue == "Added \"Ship it\" to \"Work\" (repeats weekly)")
    #expect(h.jsonData?["id"]?.stringValue == item.id)
  }

  @Test("add defaults priority to none, rejects --section and impossible dates")
  func addEdges() async throws {
    let h = Harness()
    try await h.context.add(list: "Work", title: "Plain", priority: "urgent")
    #expect(h.store.item(titled: "Plain")?.priority == Priority.none)
    #expect(h.stdout.text == "✓ Added \"Plain\" to \"Work\"\n")
    let section = await #expect(throws: RemiCommandError.self) {
      try await h.context.add(list: "Work", title: "S", section: "Later")
    }
    #expect(section?.code == .reminderKitUnavailable)
    let date = await #expect(throws: RemiCommandError.self) {
      try await h.context.add(list: "Work", title: "D", due: "2026-02-30")
    }
    #expect(date?.code == .invalidArgument)
    #expect(h.store.items.count == 1)
  }

  @Test("complete, update and delete find reminders by title")
  func mutations() async throws {
    let h = Harness()
    h.store.addItem("Milk", list: "Groceries", due: "2026-10-30")
    h.store.addItem("Bread", list: "Groceries")
    try await h.context.complete(list: "Groceries", title: "milk")
    #expect(h.store.item(titled: "Milk")?.isCompleted == true)
    try await h.context.update(list: "Groceries", title: "Bread", newTitle: "Rye", clearDue: true, priority: "low")
    #expect(h.store.item(titled: "Rye")?.priority == .low)
    try await h.context.update(list: "Groceries", title: "Rye", due: "2026-11-02", notes: "sliced")
    #expect(h.store.item(titled: "Rye")?.dueDate == "2026-11-02")
    #expect(h.store.item(titled: "Rye")?.notes == "sliced")
    try await h.context.delete(list: "Groceries", title: "Rye", confirm: true)
    #expect(h.store.item(titled: "Rye") == nil)
    #expect(
      h.stdout.text
        == "✓ Completed \"Milk\" in \"Groceries\"\n✓ Updated \"Bread\" in \"Groceries\"\n"
        + "✓ Updated \"Rye\" in \"Groceries\"\n✓ Deleted \"Rye\" from \"Groceries\"\n")
  }

  @Test("updating a completed reminder reports it as not found")
  func updateCompleted() async throws {
    let h = Harness()
    h.store.addItem("Done", list: "Work", completed: true)
    let error = await #expect(throws: RemiCommandError.self) {
      try await h.context.update(list: "Work", title: "Done", newTitle: "X")
    }
    #expect(error?.code == .reminderNotFound)
  }

  @Test("deletes need --confirm outside JSON mode")
  func confirm() async throws {
    let h = Harness()
    h.store.addItem("Milk", list: "Groceries")
    let error = await #expect(throws: RemiCommandError.self) {
      try await h.context.delete(list: "Groceries", title: "Milk", confirm: false)
    }
    #expect(error?.message == "Deletion requires --confirm flag")
    #expect(error?.suggestion == "Run: remi delete \"Groceries\" \"Milk\" --confirm")
    let listError = await #expect(throws: RemiCommandError.self) {
      try await h.context.deleteList("Groceries", confirm: false)
    }
    #expect(listError?.message == "List deletion requires --confirm flag")
    #expect(h.store.items.count == 1)

    let json = Harness(json: true)
    json.store.addItem("Milk", list: "Groceries")
    try await json.context.delete(list: "Groceries", title: "Milk", confirm: false)
    #expect(json.store.items.isEmpty)
  }

  @Test("create-list is idempotent and delete-list resolves the name")
  func listsLifecycle() async throws {
    let h = Harness(json: true)
    try await h.context.createList("Trip")
    let id = try #require(h.jsonData?["id"]?.stringValue)
    try await h.context.createList("Trip")
    #expect(h.store.storeLists.filter { $0.title == "Trip" }.count == 1)
    #expect(h.store.storeLists.first { $0.title == "Trip" }?.id == id)
    try await h.context.deleteList("trip", confirm: true)
    #expect(!h.store.storeLists.contains { $0.title == "Trip" })
  }

  /// remi's tests/integration/crud.test.ts, run against the fake store.
  @Test("CRUD lifecycle")
  func crudLifecycle() async throws {
    let h = Harness(lists: [], json: true)
    let list = "_remi_test_abc123"
    try await h.context.createList(list)
    try await h.context.add(list: list, title: "Integration test item")
    try await h.context.add(list: list, title: "Urgent task", due: "2026-12-25", priority: "high")
    try await h.context.add(list: list, title: "NLP date task", due: "tomorrow")
    try await h.context.add(list: list, title: "Recurring task", due: "2026-12-25", repeat: "weekly")
    let recurring = try #require(h.store.item(titled: "Recurring task"))
    #expect(recurring.isRecurring == true && recurring.recurrence == "weekly")
    try await h.context.complete(list: list, title: "Integration test item")
    let open = try await h.context.getReminders(listID: nil, filter: .incomplete).map(\.title)
    #expect(!open.contains("Integration test item"))
    try await h.context.update(list: list, title: "Urgent task", newTitle: "Updated task", priority: "low")
    let found = try await h.context.searchReminders("Updated task")
    #expect(found.map(\.listName) == [list])
    #expect(found.first?.priority == .low)
    try await h.context.delete(list: list, title: "NLP date task", confirm: true)
    #expect(h.store.item(titled: "NLP date task") == nil)
    try await h.context.createList(list)
    #expect(h.store.storeLists.count == 1)
    try await h.context.deleteList(list, confirm: true)
    #expect(h.store.storeLists.isEmpty)
  }
}

@Suite("doctor and authorize")
struct DiagnosticsTests {
  @Test("doctor passes on a healthy Mac")
  func healthy() async {
    let h = Harness()
    h.store.addItem("x", list: "Work")
    let ok = await h.context.doctor(system: FakeSystem())
    #expect(ok)
    #expect(
      h.stdout.text == """

        remi doctor
        ────────────────────────────────────────
        ✓ macOS version: macOS 26.0.1
        ✓ Info.plist: Embedded (io.github.neo-the-on3.remi)
        ✓ Reminders database: Found
          /Users/me/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores/Data-1.sqlite
        ✓ Reminders access: Granted (2 lists)
        ✓ Reminders data dir: Exists

        All checks passed.

        """)
  }

  @Test("doctor reports problems and emits JSON checks")
  func problems() async throws {
    let h = Harness(json: true)
    h.store.access = .denied
    let system = FakeSystem()
    system.productVersion = "15.6"
    system.embeddedInfoPlist = nil
    system.databaseFiles = nil
    system.storesExist = false
    _ = await h.context.doctor(system: system)
    let checks = try #require(h.jsonData?.arrayValue)
    #expect(checks.compactMap { $0["status"]?.stringValue } == ["fail", "warn", "warn", "fail", "fail"])
    #expect(checks[0]["message"]?.stringValue == "macOS 15.6 (requires 26+)")
    #expect(checks[2]["message"]?.stringValue == "Not accessible (Operation not permitted)")
    #expect(checks[3]["message"]?.stringValue == "Not granted")

    let undetermined = Harness()
    undetermined.store.access = .notDetermined
    #expect(await undetermined.context.doctor(system: FakeSystem()) == false)
    #expect(undetermined.stdout.text.contains("✗ Reminders access: Not requested yet\n"))
    #expect(undetermined.store.accessRequests == 0)

    let human = Harness()
    human.store.storeLists = []
    #expect(await human.context.doctor(system: FakeSystem()) == false)
    #expect(human.stdout.text.contains("✗ Reminders access: Not granted (0 lists returned)\n  Run: remi authorize\n"))
    #expect(human.stdout.text.hasSuffix("\n1 issue(s) found.\n"))
  }

  @Test("authorize opens System Settings for missing permissions")
  func authorize() async {
    let h = Harness()
    h.store.access = .denied
    let system = FakeSystem()
    system.databaseFiles = nil
    await h.context.authorize(system: system)
    #expect(system.opened == [remindersSettingsURL, fullDiskAccessSettingsURL])
    #expect(h.stdout.text.contains("   ✗ Reminders access not granted.\n"))
    #expect(h.stdout.text.hasSuffix("\nRun 'remi doctor' to verify all permissions.\n\n"))

    let granted = Harness(lists: ["One"])
    let fine = FakeSystem()
    await granted.context.authorize(system: fine)
    #expect(fine.opened.isEmpty)
    #expect(granted.stdout.text.contains("   ✓ Reminders access granted (1 list found)\n"))
    #expect(granted.stdout.text.contains("   ✓ Database access granted (Data-1.sqlite)\n"))

    let json = Harness(json: true)
    await json.context.authorize(system: FakeSystem())
    #expect(json.stdout.text.isEmpty)
  }
}
