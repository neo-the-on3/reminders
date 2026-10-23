// The boundary between remi's command logic and Apple Reminders.
//
// remi's TypeScript calls a Swift helper (src/swift/reminders-helper.swift) for every EventKit
// operation. In this port the EventKit implementation lives in RemiApple, and everything above it
// (name resolution, filtering, messages, output) is pure and runs against this protocol, so it can
// be unit-tested with an in-memory store on any platform.

/// A reminder list (EventKit calendar), without counts.
public struct StoreList: Equatable, Sendable {
  public var id: String
  public var title: String

  public init(id: String, title: String) {
    self.id = id
    self.title = title
  }
}

/// A calendar day, as stored in a reminder's due-date components.
public struct DueDay: Equatable, Hashable, Sendable, Comparable {
  public var year: Int
  public var month: Int
  public var day: Int

  public init(year: Int, month: Int, day: Int) {
    self.year = year
    self.month = month
    self.day = day
  }

  /// Parse `YYYY-MM-DD`, rejecting impossible dates (like remi helper's DateFormatter).
  public init?(_ text: String) {
    guard isISODateString(text) else { return nil }
    let parts = text.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, (1...12).contains(parts[1]), parts[2] >= 1,
      parts[2] <= DueDay.daysInMonth(year: parts[0], month: parts[1])
    else { return nil }
    self.init(year: parts[0], month: parts[1], day: parts[2])
  }

  /// `YYYY-MM-DD`
  public var string: String { formatYMD(year, month, day) }

  public static func < (lhs: DueDay, rhs: DueDay) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }

  static func daysInMonth(year: Int, month: Int) -> Int {
    switch month {
    case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
    case 4, 6, 9, 11: return 30
    default: return 31
    }
  }
}

/// Recurrence to attach to a new reminder (see ``parseRepeat(_:)``).
public struct RecurrenceRule: Equatable, Sendable {
  public enum Frequency: String, Sendable {
    case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY"
  }

  public var frequency: Frequency
  public var interval: Int
  /// EventKit weekday numbers: 1 = Sunday … 7 = Saturday.
  public var daysOfWeek: [Int]
  public var end: DueDay?

  public init(frequency: Frequency, interval: Int, daysOfWeek: [Int] = [], end: DueDay? = nil) {
    self.frequency = frequency
    self.interval = interval
    self.daysOfWeek = daysOfWeek
    self.end = end
  }

  /// Build from `--repeat` parameters. Throws like remi's helper for an unknown frequency.
  public init(_ params: RecurrenceParams) throws(RemiCommandError) {
    guard let frequency = Frequency(rawValue: params.rruleFreq.uppercased()) else {
      throw RemiCommandError(
        .invalidArgument, "Invalid frequency: \(params.rruleFreq). Use: daily, weekly, monthly, yearly")
    }
    self.init(frequency: frequency, interval: params.rruleInterval, daysOfWeek: params.rruleDays ?? [])
  }
}

/// Fields for a new reminder.
public struct NewReminder: Equatable, Sendable {
  public var title: String
  public var listID: String
  public var due: DueDay?
  public var notes: String?
  public var priority: Priority?
  public var recurrence: RecurrenceRule?

  public init(
    title: String, listID: String, due: DueDay? = nil, notes: String? = nil, priority: Priority? = nil,
    recurrence: RecurrenceRule? = nil
  ) {
    self.title = title
    self.listID = listID
    self.due = due
    self.notes = notes
    self.priority = priority
    self.recurrence = recurrence
  }
}

/// Changes to an existing reminder. Nil fields are left alone.
public struct ReminderEdit: Equatable, Sendable {
  public var title: String?
  public var due: DueDay?
  public var clearDue: Bool
  public var notes: String?
  public var priority: Priority?

  public init(
    title: String? = nil, due: DueDay? = nil, clearDue: Bool = false, notes: String? = nil, priority: Priority? = nil
  ) {
    self.title = title
    self.due = due
    self.clearDue = clearDue
    self.notes = notes
    self.priority = priority
  }
}

/// Reminders access as reported by the system.
public enum ReminderAccess: String, Sendable {
  case granted, denied, restricted, writeOnly, notDetermined
}

/// Apple Reminders operations remi needs. Implementations throw ``RemiCommandError``.
public protocol ReminderStore: AnyObject {
  /// Ask for full Reminders access (shows the system prompt the first time). Returns the resulting status.
  func requestAccess() async throws -> ReminderAccess
  /// Current status without prompting.
  func accessStatus() -> ReminderAccess

  /// All reminder lists, in store order.
  func lists() async throws -> [StoreList]
  /// Reminders in the given lists (all lists when nil), either incomplete or completed ones.
  func reminders(inLists listIDs: [String]?, completed: Bool) async throws -> [Reminder]

  /// Create a reminder; returns its identifier.
  func createReminder(_ reminder: NewReminder) async throws -> String
  /// Edit an incomplete reminder; returns its (new) title.
  func editReminder(id: String, _ edit: ReminderEdit) async throws -> String
  /// Mark an incomplete reminder complete; returns its title.
  func completeReminder(id: String) async throws -> String
  /// Delete a reminder (complete or not); returns its title.
  func deleteReminder(id: String) async throws -> String

  /// Create a list in the default reminders source; returns its identifier.
  func createList(title: String) async throws -> String
  /// Delete a list.
  func deleteList(id: String) async throws
}
