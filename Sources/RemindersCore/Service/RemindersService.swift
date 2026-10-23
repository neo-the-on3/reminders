import Foundation

/// The reminder commands, independent of where reminders live and how results are shown.
///
/// Every operation checks access first: when the user hasn't been asked yet it asks (the system prompt), and any
/// other answer than full access fails with `PERMISSION_DENIED`.
public struct RemindersService: Sendable {
  public let store: any ReminderStore
  public var clock: DayClock

  public init(store: any ReminderStore, clock: DayClock = DayClock()) {
    self.store = store
    self.clock = clock
  }

  public static let permissionDenied = RemindersError(
    .permissionDenied, "Reminders access not granted",
    suggestion: "Run: reminders authorize (then check System Settings > Privacy & Security > Reminders)")

  public func ensureAccess() async throws(RemindersError) {
    var access = await store.accessStatus()
    if access == .notDetermined { access = try await store.requestFullAccess() }
    switch access {
    case .fullAccess: return
    case .unavailable: throw .unsupportedPlatform
    case .writeOnly, .denied, .restricted, .notDetermined: throw Self.permissionDenied
    }
  }

  // MARK: Queries

  /// All lists, sorted by title, with their incomplete and overdue counts.
  public func lists() async throws(RemindersError) -> [ReminderList] {
    try await ensureAccess()
    let lists = try await store.lists()
    let incomplete = try await store.reminders(inLists: nil, .incomplete)
    let byList = Dictionary(grouping: incomplete, by: \.listID)
    return lists.map { list in
      var list = list
      let reminders = byList[list.id] ?? []
      list.reminderCount = reminders.count
      list.overdueCount = reminders.count { isDueDayStarted($0) }
      return list
    }
    .sorted { $0.title < $1.title }
  }

  /// `reminders lists`
  public func listOverview() async throws(RemindersError) -> ListOverview {
    ListOverview(try await lists())
  }

  /// `reminders list <name>`: the list's incomplete reminders, then (optionally) its completed ones.
  public func contents(ofList name: String, includeCompleted: Bool = false) async throws(RemindersError)
    -> ReminderListing
  {
    let list = try await lists().resolve(name)
    var reminders = try await store.reminders(inLists: [list.id], .incomplete)
    if includeCompleted { reminders += try await store.reminders(inLists: [list.id], .completed) }
    return ReminderListing(reminders, heading: list.title, layout: .list)
  }

  /// `reminders today`: incomplete reminders due today.
  public func dueToday() async throws(RemindersError) -> ReminderListing {
    let today = clock.today
    return ReminderListing(try await incomplete { $0.dueDate == today }, heading: "Due Today", layout: .today)
  }

  /// `reminders overdue`: incomplete reminders due before today.
  public func overdue() async throws(RemindersError) -> ReminderListing {
    let today = clock.today
    let reminders = try await incomplete { $0.dueDate.map { $0 < today } ?? false }
    return ReminderListing(reminders, heading: "Overdue", layout: .overdue)
  }

  /// `reminders upcoming`: incomplete reminders due within `days` days from now, overdue ones included.
  public func upcoming(days: Int) async throws(RemindersError) -> ReminderListing {
    let horizon = clock.calendar.date(byAdding: .day, value: days, to: clock.now) ?? clock.now
    let reminders = try await incomplete { reminder in
      guard let start = reminder.dueDate?.startDate(in: clock.calendar) else { return false }
      return start <= horizon
    }
    return ReminderListing(reminders, heading: "Due in next \(days) days", layout: .upcoming)
  }

  /// `reminders search`: incomplete reminders whose title or notes contain `query`, ignoring case.
  public func search(_ query: String) async throws(RemindersError) -> ReminderListing {
    let reminders = try await incomplete { reminder in
      reminder.title.localizedStandardContains(query) || (reminder.notes?.localizedStandardContains(query) ?? false)
    }
    return ReminderListing(reminders, heading: "Search: \"\(query)\"", layout: .search)
  }

  // MARK: Reminder changes

  /// `reminders add`
  public func add(_ request: NewReminderRequest) async throws(RemindersError) -> Confirmation {
    let list = try await lists().resolve(request.list)
    let id = try await store.createReminder(
      ReminderDraft(
        title: request.title, listID: list.id, dueDate: try request.due.map(parseDueDate), notes: request.notes,
        priority: request.priority, recurrence: try request.repeatRule.map(Recurrence.init(parsing:))))
    var message = "Added \"\(request.title)\" to \"\(list.title)\""
    if let repeatRule = request.repeatRule { message += " (repeats \(repeatRule))" }
    return Confirmation(message, id: id)
  }

  /// `reminders complete`
  public func complete(_ reference: ReminderReference) async throws(RemindersError) -> Confirmation {
    let (list, reminder) = try await find(reference)
    try await store.completeReminder(id: reminder.id)
    return Confirmation("Completed \"\(reminder.title)\" in \"\(list.title)\"")
  }

  /// `reminders update`
  public func update(_ reference: ReminderReference, _ edit: ReminderEdit) async throws(RemindersError)
    -> Confirmation
  {
    let dueDate: ReminderChanges.DueDateChange? =
      if edit.clearDue { .remove } else {
        try edit.due.map { text throws(RemindersError) in .set(try parseDueDate(text)) }
      }
    let (list, reminder) = try await find(reference)
    try await store.updateReminder(
      id: reminder.id,
      ReminderChanges(title: edit.title, dueDate: dueDate, notes: edit.notes, priority: edit.priority))
    return Confirmation("Updated \"\(reminder.title)\" in \"\(list.title)\"")
  }

  /// `reminders delete`
  public func delete(_ reference: ReminderReference) async throws(RemindersError) -> Confirmation {
    let (list, reminder) = try await find(reference)
    try await store.deleteReminder(id: reminder.id)
    return Confirmation("Deleted \"\(reminder.title)\" from \"\(list.title)\"")
  }

  // MARK: List changes

  /// `reminders create-list`. A list with exactly that title is reused rather than duplicated.
  public func createList(named name: String) async throws(RemindersError) -> Confirmation {
    try await ensureAccess()
    let id: String
    if let existing = try await store.lists().first(where: { $0.title == name }) {
      id = existing.id
    } else {
      id = try await store.createList(title: name)
    }
    return Confirmation("Created list \"\(name)\"", id: id)
  }

  /// `reminders delete-list`, with its reminders.
  public func deleteList(named name: String) async throws(RemindersError) -> Confirmation {
    let list = try await lists().resolve(name)
    try await store.deleteList(id: list.id)
    return Confirmation("Deleted list \"\(list.title)\"")
  }

  // MARK: Helpers

  private func incomplete(where isIncluded: (Reminder) -> Bool) async throws(RemindersError) -> [Reminder] {
    try await ensureAccess()
    return try await store.reminders(inLists: nil, .incomplete).filter(isIncluded)
  }

  /// Finds a reminder, complete or not, by title (or ID prefix) in a list.
  private func find(_ reference: ReminderReference) async throws(RemindersError) -> (ReminderList, Reminder) {
    let list = try await lists().resolve(reference.list)
    let reminders =
      try await store.reminders(inLists: [list.id], .incomplete)
      + store.reminders(inLists: [list.id], .completed)
    return (list, try reminders.find(title: reference.title, idPrefix: reference.id, inList: list.title))
  }

  /// Whether the reminder's due day has begun, which is how list counts define overdue (due today counts).
  private func isDueDayStarted(_ reminder: Reminder) -> Bool {
    guard let start = reminder.dueDate?.startDate(in: clock.calendar) else { return false }
    return start < clock.now
  }

  private func parseDueDate(_ text: String) throws(RemindersError) -> CalendarDay {
    try DueDateParser(clock: clock).parse(text)
  }
}

/// Which reminder a command means: a title (or `--id` prefix) within a list.
public struct ReminderReference: Sendable, Hashable {
  public var list: String
  public var title: String
  public var id: String?

  public init(list: String, title: String, id: String? = nil) {
    self.list = list
    self.title = title
    self.id = id
  }
}

/// `reminders add` arguments, as typed.
public struct NewReminderRequest: Sendable, Hashable {
  public var list: String
  public var title: String
  public var due: String?
  public var priority: Priority
  public var notes: String?
  public var repeatRule: String?

  public init(
    list: String, title: String, due: String? = nil, priority: Priority = .none, notes: String? = nil,
    repeatRule: String? = nil
  ) {
    self.list = list
    self.title = title
    self.due = due
    self.priority = priority
    self.notes = notes
    self.repeatRule = repeatRule
  }
}

/// `reminders update` options, as typed. Nil fields stay as they are.
public struct ReminderEdit: Sendable, Hashable {
  public var title: String?
  public var due: String?
  public var clearDue: Bool
  public var priority: Priority?
  public var notes: String?

  public init(
    title: String? = nil, due: String? = nil, clearDue: Bool = false, priority: Priority? = nil, notes: String? = nil
  ) {
    self.title = title
    self.due = due
    self.clearDue = clearDue
    self.priority = priority
    self.notes = notes
  }
}
