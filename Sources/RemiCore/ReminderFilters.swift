// Ported from the filtering in remi src/swift/reminders-helper.swift (listLists, getReminders, search).

import Foundation

/// Reminder selections used by remi's commands (the helper's `get-reminders` filters).
public enum ReminderFilter: Equatable, Sendable {
  /// Incomplete reminders.
  case incomplete
  /// Incomplete and completed reminders.
  case all
  /// Completed reminders.
  case completed
  /// Incomplete, due today.
  case today
  /// Incomplete, due tomorrow.
  case tomorrow
  /// Incomplete, due on or before now + 7 days (includes overdue).
  case week
  /// Incomplete, due on or before now + `days` days (includes overdue).
  case upcoming(days: Int)
  /// Incomplete, due before today.
  case overdue
  /// Incomplete, due on that day.
  case on(DueDay)
}

/// Date arithmetic in the user's zone, matching the helper's `Calendar.current` logic.
public struct ReminderClock: Sendable {
  public var now: Date
  public var timeZone: TimeZone

  public init(now: Date = Date(), timeZone: TimeZone = .current) {
    self.now = now
    self.timeZone = timeZone
  }

  var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }

  /// Local midnight at the start of `day` (what `dateFormatter.date(from: "YYYY-MM-DD")` yields).
  func midnight(_ day: DueDay) -> Date? {
    calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day))
  }

  func dueDay(of date: Date) -> DueDay {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return DueDay(year: c.year ?? 0, month: c.month ?? 1, day: c.day ?? 1)
  }

  var today: DueDay { dueDay(of: now) }

  func adding(days: Int) -> Date {
    calendar.date(byAdding: .day, value: days, to: now) ?? now
  }

  /// remi counts a list's reminder as overdue when its due day's midnight has passed (so due today counts).
  func isOverdueForListCount(_ reminder: Reminder) -> Bool {
    guard let day = reminder.dueDate.flatMap(DueDay.init), let midnight = midnight(day) else { return false }
    return midnight < now
  }

  /// Apply a non-completion filter to incomplete reminders.
  func matches(_ reminder: Reminder, _ filter: ReminderFilter) -> Bool {
    switch filter {
    case .incomplete, .all, .completed: return true
    default: break
    }
    guard let day = reminder.dueDate.flatMap(DueDay.init), let midnight = midnight(day) else { return false }
    switch filter {
    case .today: return day == today
    case .tomorrow: return day == dueDay(of: adding(days: 1))
    case .week: return midnight <= adding(days: 7)
    case .upcoming(let days): return midnight <= adding(days: days)
    case .overdue: return midnight < calendar.startOfDay(for: now)
    case .on(let target): return day == target
    case .incomplete, .all, .completed: return true
    }
  }
}

/// remi's search: case-insensitive substring of the title or notes.
public func reminderMatchesSearch(_ reminder: Reminder, query: String) -> Bool {
  let q = query.lowercased()
  return reminder.title.lowercased().contains(q) || (reminder.notes?.lowercased().contains(q) ?? false)
}

// MARK: - Mapping helpers shared with the EventKit layer

/// EventKit priority (0–9) → remi priority.
public func priority(fromEventKit value: Int) -> Priority {
  switch value {
  case 1...4: return .high
  case 5: return .medium
  case 6...9: return .low
  default: return .none
  }
}

/// remi priority → EventKit priority.
public func eventKitPriority(_ priority: Priority) -> Int {
  switch priority {
  case .high: return 1
  case .medium: return 5
  case .low: return 9
  case .none: return 0
  }
}

/// remi's human-readable recurrence, e.g. "weekly", "every 2 weeks", "weekly on Mon, Fri".
/// - Parameter daysOfWeek: EventKit weekday numbers (1 = Sunday … 7 = Saturday).
public func describeRecurrence(frequency: RecurrenceRule.Frequency, interval: Int, daysOfWeek: [Int]) -> String {
  let unit: String
  switch frequency {
  case .daily: unit = "day"
  case .weekly: unit = "week"
  case .monthly: unit = "month"
  case .yearly: unit = "year"
  }
  var text = interval == 1 ? (unit == "day" ? "daily" : unit + "ly") : "every \(interval) \(unit)s"
  if frequency == .weekly && !daysOfWeek.isEmpty {
    let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    text += " on " + daysOfWeek.map { (1...7).contains($0) ? names[$0 - 1] : "?" }.joined(separator: ", ")
  }
  return text
}
