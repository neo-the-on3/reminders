// Ported from remi src/types.ts (MIT, Matthew O'Riordan).
//
// JSON key order mirrors the TypeScript interfaces so `--json` output is byte-identical,
// and optional fields are omitted when nil (as JSON.stringify drops `undefined`).

/// A reminder list (calendar) in Apple Reminders.
public struct ReminderList: Equatable, Sendable, Codable {
  public var id: String
  public var title: String
  public var reminderCount: Int
  public var overdueCount: Int

  public init(id: String, title: String, reminderCount: Int, overdueCount: Int) {
    self.id = id
    self.title = title
    self.reminderCount = reminderCount
    self.overdueCount = overdueCount
  }
}

/// Priority levels matching Apple Reminders.
public enum Priority: String, CaseIterable, Equatable, Sendable, Codable {
  case none, low, medium, high
}

/// A single reminder item.
public struct Reminder: Equatable, Sendable, Codable {
  public var id: String
  public var title: String
  public var isCompleted: Bool
  public var listID: String
  public var listName: String
  public var priority: Priority
  public var dueDate: String?
  public var completionDate: String?
  public var notes: String?
  public var section: String?
  public var isRecurring: Bool?
  public var recurrence: String?
  public var flagged: Bool?

  public init(
    id: String, title: String, isCompleted: Bool = false, listID: String = "", listName: String = "",
    priority: Priority = .none, dueDate: String? = nil, completionDate: String? = nil, notes: String? = nil,
    section: String? = nil, isRecurring: Bool? = nil, recurrence: String? = nil, flagged: Bool? = nil
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
    self.section = section
    self.isRecurring = isRecurring
    self.recurrence = recurrence
    self.flagged = flagged
  }
}

/// A section within a reminder list.
public struct Section: Equatable, Sendable, Codable {
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

/// Options for adding a reminder.
public struct AddReminderOptions: Equatable, Sendable {
  public var list: String
  public var title: String
  public var section: String?
  public var due: String?
  public var priority: Priority?
  public var notes: String?

  public init(
    list: String, title: String, section: String? = nil, due: String? = nil, priority: Priority? = nil,
    notes: String? = nil
  ) {
    self.list = list
    self.title = title
    self.section = section
    self.due = due
    self.priority = priority
    self.notes = notes
  }
}

/// Options for updating a reminder.
public struct UpdateReminderOptions: Equatable, Sendable {
  public var list: String
  public var title: String
  public var newTitle: String?
  public var due: String?
  public var clearDue: Bool?
  public var priority: Priority?
  public var notes: String?

  public init(
    list: String, title: String, newTitle: String? = nil, due: String? = nil, clearDue: Bool? = nil,
    priority: Priority? = nil, notes: String? = nil
  ) {
    self.list = list
    self.title = title
    self.newTitle = newTitle
    self.due = due
    self.clearDue = clearDue
    self.priority = priority
    self.notes = notes
  }
}

/// Section membership entry (public, normalised view of the SQLite membership blob).
public struct MembershipEntry: Equatable, Sendable, Codable {
  public var reminderID: String
  public var sectionID: String

  public init(reminderID: String, sectionID: String) {
    self.reminderID = reminderID
    self.sectionID = sectionID
  }
}

/// Membership data structure returned by `getMemberships`.
public struct MembershipData: Equatable, Sendable, Codable {
  public var memberships: [MembershipEntry]

  public init(memberships: [MembershipEntry]) {
    self.memberships = memberships
  }
}

/// Token map entry for a single syncable field.
public struct TokenMapEntry: Equatable, Sendable, Codable {
  public var counter: Int
  public var modificationTime: Double

  public init(counter: Int, modificationTime: Double) {
    self.counter = counter
    self.modificationTime = modificationTime
  }
}

/// Resolution token map (CRDT vector clocks for sync), keyed by field name.
public typealias TokenMap = [String: TokenMapEntry]

// MARK: - JSON representations (TypeScript property order)

extension ReminderList: JSONValueConvertible {
  public var jsonValue: JSONValue {
    .object([
      ("id", .string(id)), ("title", .string(title)),
      ("reminderCount", .number(Double(reminderCount))), ("overdueCount", .number(Double(overdueCount))),
    ])
  }
}

extension Reminder: JSONValueConvertible {
  public var jsonValue: JSONValue {
    var fields: [(String, JSONValue)] = [
      ("id", .string(id)), ("title", .string(title)), ("isCompleted", .bool(isCompleted)),
      ("listID", .string(listID)), ("listName", .string(listName)), ("priority", .string(priority.rawValue)),
    ]
    if let dueDate { fields.append(("dueDate", .string(dueDate))) }
    if let completionDate { fields.append(("completionDate", .string(completionDate))) }
    if let notes { fields.append(("notes", .string(notes))) }
    if let section { fields.append(("section", .string(section))) }
    if let isRecurring { fields.append(("isRecurring", .bool(isRecurring))) }
    if let recurrence { fields.append(("recurrence", .string(recurrence))) }
    if let flagged { fields.append(("flagged", .bool(flagged))) }
    return .object(fields)
  }
}

extension Section: JSONValueConvertible {
  public var jsonValue: JSONValue {
    .object([
      ("id", .string(id)), ("displayName", .string(displayName)), ("listName", .string(listName)),
      ("sortOrder", .number(Double(sortOrder))),
    ])
  }
}

extension MembershipEntry: JSONValueConvertible {
  public var jsonValue: JSONValue {
    .object([("reminderID", .string(reminderID)), ("sectionID", .string(sectionID))])
  }
}

extension MembershipData: JSONValueConvertible {
  public var jsonValue: JSONValue { .object([("memberships", memberships.jsonValue)]) }
}

extension TokenMapEntry: JSONValueConvertible {
  public var jsonValue: JSONValue {
    .object([("counter", .number(Double(counter))), ("modificationTime", .number(modificationTime))])
  }
}
