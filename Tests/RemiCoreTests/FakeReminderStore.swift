// An in-memory ReminderStore with the same semantics as RemiApple's EventKitStore (and remi's helper):
// edit/complete only see incomplete reminders, delete sees all, IDs are matched by prefix.

import Foundation

@testable import RemiCore

final class FakeReminderStore: ReminderStore {
  var access: ReminderAccess = .granted
  var storeLists: [StoreList] = []
  var items: [Reminder] = []
  private var nextID = 1
  private(set) var accessRequests = 0

  init(lists: [String] = []) {
    for title in lists { _ = addList(title) }
  }

  @discardableResult
  func addList(_ title: String) -> String {
    let id = "LIST-\(nextID)"
    nextID += 1
    storeLists.append(StoreList(id: id, title: title))
    return id
  }

  @discardableResult
  func addItem(
    _ title: String, list: String, due: String? = nil, notes: String? = nil, priority: Priority = .none,
    completed: Bool = false
  ) -> String {
    let listID = storeLists.first { $0.title == list }!.id
    let id = "REM-\(nextID)"
    nextID += 1
    items.append(
      Reminder(
        id: id, title: title, isCompleted: completed, listID: listID, listName: list, priority: priority,
        dueDate: due, completionDate: completed ? "2026-10-01T09:00:00Z" : nil, notes: notes, isRecurring: false))
    return id
  }

  func item(titled title: String) -> Reminder? { items.first { $0.title == title } }

  func requestAccess() async throws -> ReminderAccess {
    accessRequests += 1
    return access
  }

  func accessStatus() -> ReminderAccess { access }

  func lists() async throws -> [StoreList] { storeLists }

  func reminders(inLists listIDs: [String]?, completed: Bool) async throws -> [Reminder] {
    items.filter { $0.isCompleted == completed && (listIDs?.contains($0.listID) ?? true) }
  }

  func createReminder(_ new: NewReminder) async throws -> String {
    guard let list = storeLists.first(where: { $0.id == new.listID }) else {
      throw RemiCommandError(.listNotFound, "List not found")
    }
    let id = "REM-\(nextID)"
    nextID += 1
    let recurrence = new.recurrence.map {
      describeRecurrence(frequency: $0.frequency, interval: $0.interval, daysOfWeek: $0.daysOfWeek)
    }
    items.append(
      Reminder(
        id: id, title: new.title, isCompleted: false, listID: list.id, listName: list.title,
        priority: new.priority ?? .none, dueDate: new.due?.string, notes: new.notes, isRecurring: recurrence != nil,
        recurrence: recurrence))
    return id
  }

  private func index(of id: String, includeCompleted: Bool) throws -> Int {
    guard let index = items.firstIndex(where: { $0.id.hasPrefix(id) && (includeCompleted || !$0.isCompleted) }) else {
      throw RemiCommandError(.reminderNotFound, "Reminder '\(id)' not found")
    }
    return index
  }

  func editReminder(id: String, _ edit: ReminderEdit) async throws -> String {
    let i = try index(of: id, includeCompleted: false)
    if let title = edit.title { items[i].title = title }
    if edit.clearDue { items[i].dueDate = nil } else if let due = edit.due { items[i].dueDate = due.string }
    if let notes = edit.notes { items[i].notes = notes }
    if let priority = edit.priority { items[i].priority = priority }
    return items[i].title
  }

  func completeReminder(id: String) async throws -> String {
    let i = try index(of: id, includeCompleted: false)
    items[i].isCompleted = true
    items[i].completionDate = "2026-10-23T10:00:00Z"
    return items[i].title
  }

  func deleteReminder(id: String) async throws -> String {
    let i = try index(of: id, includeCompleted: true)
    return items.remove(at: i).title
  }

  func createList(title: String) async throws -> String { addList(title) }

  func deleteList(id: String) async throws {
    guard storeLists.contains(where: { $0.id == id }) else { throw RemiCommandError(.listNotFound, "List not found") }
    storeLists.removeAll { $0.id == id }
    items.removeAll { $0.listID == id }
  }
}

final class FakeSystem: SystemEnvironment {
  var productVersion: String? = "26.0.1"
  var embeddedInfoPlist: [String: String]? = [
    "CFBundleIdentifier": remiBundleIdentifier, "NSRemindersFullAccessUsageDescription": "x",
  ]
  var remindersStoresPath = "/Users/me/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores"
  var storesExist = true
  var databaseFiles: [String]? = [
    "/Users/me/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores/Data-1.sqlite"
  ]
  private(set) var opened: [String] = []

  func remindersStoresExist() -> Bool { storesExist }

  func remindersDatabaseFiles() throws -> [String] {
    guard let databaseFiles else { throw RemiCommandError(.permissionDenied, "Operation not permitted") }
    return databaseFiles
  }

  func open(_ url: String) -> Bool {
    opened.append(url)
    return true
  }
}

/// A command context over a fake store, with a frozen clock (Friday 2026-10-23 10:00 UTC) and captured output.
struct Harness {
  let store: FakeReminderStore
  let context: CommandContext
  let stdout = StringSink()
  let stderr = StringSink()

  init(lists: [String] = ["Groceries", "Work"], json: Bool = false) {
    store = FakeReminderStore(lists: lists)
    let now = ISO8601DateFormatter().date(from: "2026-10-23T10:00:00Z")!
    let utc = TimeZone(identifier: "UTC")!
    let output = Output(jsonMode: json, stdout: stdout, stderr: stderr, now: { now }, timeZone: utc)
    context = CommandContext(store: store, output: output, clock: ReminderClock(now: now, timeZone: utc))
  }

  /// The `data` of a JSON-mode success response.
  var jsonData: JSONValue? { (try? JSONValue.parse(stdout.text))?["data"] }
}
