import Foundation

/// Priority levels as Apple Reminders shows them.
public enum Priority: String, CaseIterable, Hashable, Sendable, Codable {
  case none, low, medium, high

  /// EventKit's 0–9 scale: 1–4 high, 5 medium, 6–9 low, 0 none.
  public init(eventKitValue value: Int) {
    switch value {
    case 1...4: self = .high
    case 5: self = .medium
    case 6...9: self = .low
    default: self = .none
    }
  }

  /// The value Reminders.app itself writes for this priority.
  public var eventKitValue: Int {
    switch self {
    case .high: 1
    case .medium: 5
    case .low: 9
    case .none: 0
    }
  }
}

/// A reminder list, with the counts `reminders lists` shows.
public struct ReminderList: Identifiable, Hashable, Sendable, Codable {
  public var id: String
  public var title: String
  /// Incomplete reminders in the list.
  public var reminderCount: Int
  /// Incomplete reminders whose due day has started.
  public var overdueCount: Int

  public init(id: String, title: String, reminderCount: Int = 0, overdueCount: Int = 0) {
    self.id = id
    self.title = title
    self.reminderCount = reminderCount
    self.overdueCount = overdueCount
  }
}

/// A single reminder.
public struct Reminder: Identifiable, Hashable, Sendable {
  public var id: String
  public var title: String
  public var isCompleted: Bool
  public var listID: String
  public var listName: String
  public var priority: Priority
  public var dueDate: CalendarDay?
  public var completionDate: Date?
  public var notes: String?
  /// How the reminder repeats. A repeating reminder whose rule can't be described has ``isRecurring`` set and no
  /// recurrence.
  public var recurrence: Recurrence?
  public var isRecurring: Bool
  /// Section name, when known.
  public var section: String?
  /// Flag state, when known.
  public var isFlagged: Bool?

  public init(
    id: String, title: String, isCompleted: Bool = false, listID: String = "", listName: String = "",
    priority: Priority = .none, dueDate: CalendarDay? = nil, completionDate: Date? = nil, notes: String? = nil,
    recurrence: Recurrence? = nil, isRecurring: Bool? = nil, section: String? = nil, isFlagged: Bool? = nil
  ) {
    self.id = id
    self.title = title
    self.isCompleted = isCompleted
    self.listID = listID
    self.listName = listName
    self.priority = priority
    self.dueDate = dueDate
    self.completionDate = completionDate
    self.notes = notes
    self.recurrence = recurrence
    self.isRecurring = isRecurring ?? (recurrence != nil)
    self.section = section
    self.isFlagged = isFlagged
  }
}

extension Reminder: Encodable {
  private enum CodingKeys: String, CodingKey {
    case id, title, isCompleted, listID, listName, priority, dueDate, completionDate, notes, section, isRecurring,
      recurrence, flagged
  }

  /// The `--json` shape: `dueDate` as `YYYY-MM-DD`, `completionDate` as ISO 8601, `recurrence` as its description.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encode(isCompleted, forKey: .isCompleted)
    try container.encode(listID, forKey: .listID)
    try container.encode(listName, forKey: .listName)
    try container.encode(priority, forKey: .priority)
    try container.encodeIfPresent(dueDate, forKey: .dueDate)
    try container.encodeIfPresent(completionDate.map(Self.formatTimestamp), forKey: .completionDate)
    try container.encodeIfPresent(notes, forKey: .notes)
    try container.encodeIfPresent(section, forKey: .section)
    try container.encode(isRecurring, forKey: .isRecurring)
    try container.encodeIfPresent(recurrence?.description, forKey: .recurrence)
    try container.encodeIfPresent(isFlagged, forKey: .flagged)
  }

  static func formatTimestamp(_ date: Date) -> String {
    date.formatted(.iso8601)
  }
}

/// A section (group of reminders) within a list.
public struct Section: Identifiable, Hashable, Sendable, Codable {
  public var id: String
  public var displayName: String
  public var listName: String
  public var sortOrder: Int

  public init(id: String, displayName: String, listName: String, sortOrder: Int) {
    self.id = id
    self.displayName = displayName
    self.listName = listName
    self.sortOrder = sortOrder
  }
}
