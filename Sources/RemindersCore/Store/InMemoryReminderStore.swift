import Foundation

/// A ``ReminderStore`` kept in memory, for tests and previews. Behaves like the EventKit store: unknown identifiers
/// fail with `LIST_NOT_FOUND` / `REMINDER_NOT_FOUND`, and nothing works until access is granted.
public actor InMemoryReminderStore: ReminderStore {
  public private(set) var access: ReminderAccess
  /// What ``requestFullAccess()`` grants when access hasn't been decided yet (the user's answer to the prompt).
  public var promptAnswer: ReminderAccess
  private var storedLists: [ReminderList]
  private var storedReminders: [Reminder]
  private var nextID = 1
  /// When reminders are marked complete.
  public var now: @Sendable () -> Date

  public init(
    lists: [ReminderList] = [], reminders: [Reminder] = [], access: ReminderAccess = .fullAccess,
    promptAnswer: ReminderAccess = .fullAccess, now: @escaping @Sendable () -> Date = { .now }
  ) {
    self.storedLists = lists
    self.storedReminders = reminders
    self.access = access
    self.promptAnswer = promptAnswer
    self.now = now
  }

  /// Every reminder, complete or not, in creation order.
  public var allReminders: [Reminder] { storedReminders }

  public func setAccess(_ access: ReminderAccess) {
    self.access = access
  }

  public func accessStatus() -> ReminderAccess { access }

  public func requestFullAccess() -> ReminderAccess {
    if access == .notDetermined { access = promptAnswer }
    return access
  }

  public func lists() throws(RemindersError) -> [ReminderList] {
    try requireAccess()
    return storedLists
  }

  public func reminders(inLists listIDs: [String]?, _ filter: CompletionFilter) throws(RemindersError) -> [Reminder] {
    try requireAccess()
    if let listIDs {
      for id in listIDs { _ = try list(id: id) }
    }
    return storedReminders.filter { reminder in
      reminder.isCompleted == (filter == .completed) && (listIDs?.contains(reminder.listID) ?? true)
    }
  }

  public func createReminder(_ draft: ReminderDraft) throws(RemindersError) -> String {
    try requireAccess()
    let list = try list(id: draft.listID)
    let id = makeID()
    storedReminders.append(
      Reminder(
        id: id, title: draft.title, listID: list.id, listName: list.title, priority: draft.priority,
        dueDate: draft.dueDate, notes: draft.notes, recurrence: draft.recurrence))
    return id
  }

  public func updateReminder(id: String, _ changes: ReminderChanges) throws(RemindersError) {
    try modifyReminder(id: id) { reminder in
      if let title = changes.title { reminder.title = title }
      if let notes = changes.notes { reminder.notes = notes }
      if let priority = changes.priority { reminder.priority = priority }
      switch changes.dueDate {
      case .set(let day): reminder.dueDate = day
      case .remove: reminder.dueDate = nil
      case nil: break
      }
    }
  }

  public func completeReminder(id: String) throws(RemindersError) {
    let completionDate = now()
    try modifyReminder(id: id) { reminder in
      reminder.isCompleted = true
      reminder.completionDate = completionDate
    }
  }

  public func deleteReminder(id: String) throws(RemindersError) {
    try requireAccess()
    guard let index = storedReminders.firstIndex(where: { $0.id == id }) else { throw Self.reminderNotFound(id) }
    storedReminders.remove(at: index)
  }

  public func createList(title: String) throws(RemindersError) -> String {
    try requireAccess()
    let id = makeID()
    storedLists.append(ReminderList(id: id, title: title))
    return id
  }

  public func deleteList(id: String) throws(RemindersError) {
    try requireAccess()
    _ = try list(id: id)
    storedLists.removeAll { $0.id == id }
    storedReminders.removeAll { $0.listID == id }
  }

  // MARK: Helpers

  private func requireAccess() throws(RemindersError) {
    guard access == .fullAccess else { throw RemindersError(.permissionDenied, "Reminders access not granted") }
  }

  private func list(id: String) throws(RemindersError) -> ReminderList {
    guard let list = storedLists.first(where: { $0.id == id }) else {
      throw RemindersError(.listNotFound, "List '\(id)' not found")
    }
    return list
  }

  private func modifyReminder(id: String, _ change: (inout Reminder) -> Void) throws(RemindersError) {
    try requireAccess()
    guard let index = storedReminders.firstIndex(where: { $0.id == id }) else { throw Self.reminderNotFound(id) }
    change(&storedReminders[index])
  }

  private func makeID() -> String {
    defer { nextID += 1 }
    return String(format: "%08X-0000-4000-8000-%012X", nextID, nextID)
  }

  private static func reminderNotFound(_ id: String) -> RemindersError {
    RemindersError(.reminderNotFound, "Reminder '\(id)' not found")
  }
}
