/// Whether this process may read and write reminders.
public enum ReminderAccess: String, Sendable, Hashable, Codable {
  case fullAccess, writeOnly, denied, restricted, notDetermined
  /// There is no Apple Reminders on this platform.
  case unavailable
}

/// Which reminders a query returns.
public enum CompletionFilter: Sendable, Hashable {
  case incomplete, completed
}

/// Everything needed to create a reminder.
public struct ReminderDraft: Sendable, Hashable {
  public var title: String
  public var listID: String
  public var dueDate: CalendarDay?
  public var notes: String?
  public var priority: Priority
  public var recurrence: Recurrence?

  public init(
    title: String, listID: String, dueDate: CalendarDay? = nil, notes: String? = nil, priority: Priority = .none,
    recurrence: Recurrence? = nil
  ) {
    self.title = title
    self.listID = listID
    self.dueDate = dueDate
    self.notes = notes
    self.priority = priority
    self.recurrence = recurrence
  }
}

/// Edits to an existing reminder. Nil fields stay as they are.
public struct ReminderChanges: Sendable, Hashable {
  public enum DueDateChange: Sendable, Hashable {
    case set(CalendarDay)
    case remove
  }

  public var title: String?
  public var dueDate: DueDateChange?
  public var notes: String?
  public var priority: Priority?

  public init(title: String? = nil, dueDate: DueDateChange? = nil, notes: String? = nil, priority: Priority? = nil) {
    self.title = title
    self.dueDate = dueDate
    self.notes = notes
    self.priority = priority
  }
}

/// The reminders database the commands work against: Apple Reminders through EventKit on macOS, or an in-memory
/// store in tests. Identifiers are the store's own (EventKit calendar and calendar-item identifiers).
public protocol ReminderStore: Sendable {
  /// Current access, without asking the user.
  func accessStatus() async -> ReminderAccess
  /// Asks for full access (the system shows its prompt the first time) and returns the resulting access.
  func requestFullAccess() async throws(RemindersError) -> ReminderAccess

  /// All reminder lists, in the store's order. Their counts are not filled in.
  func lists() async throws(RemindersError) -> [ReminderList]
  /// Reminders in the given lists (every list when nil).
  func reminders(inLists listIDs: [String]?, _ filter: CompletionFilter) async throws(RemindersError) -> [Reminder]

  /// Creates a reminder and returns its identifier.
  func createReminder(_ draft: ReminderDraft) async throws(RemindersError) -> String
  func updateReminder(id: String, _ changes: ReminderChanges) async throws(RemindersError)
  func completeReminder(id: String) async throws(RemindersError)
  func deleteReminder(id: String) async throws(RemindersError)

  /// Creates a list in the default account and returns its identifier.
  func createList(title: String) async throws(RemindersError) -> String
  func deleteList(id: String) async throws(RemindersError)
}
