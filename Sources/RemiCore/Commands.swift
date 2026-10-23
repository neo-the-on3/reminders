// Ported from remi src/cli/commands/*.ts, src/core/resolve.ts and src/core/lookup.ts (MIT, Matthew O'Riordan).
//
// Each function is one CLI command. They talk to Apple Reminders only through ``ReminderStore`` and print
// only through ``Output``, so they behave identically against EventKit and against the in-memory store
// used by the unit tests.

/// What every command needs.
public final class CommandContext {
  public let store: any ReminderStore
  public let output: Output
  public var clock: ReminderClock

  public init(store: any ReminderStore, output: Output, clock: ReminderClock = ReminderClock()) {
    self.store = store
    self.output = output
    self.clock = clock
  }

  // MARK: Access

  /// remi's helper requests full access before every operation and fails with this error when refused.
  public func ensureAccess() async throws {
    let access = try await store.requestAccess()
    guard access == .granted else { throw Self.permissionDenied }
  }

  static let permissionDenied = RemiCommandError(
    .permissionDenied, "Reminders access not granted",
    suggestion: "Run: remi authorize (then check System Settings > Privacy & Security > Reminders)")

  // MARK: Queries (eventkit.ts listLists / getReminders / searchReminders)

  /// Lists with reminder and overdue counts, sorted by title (helper `list-lists`).
  public func listLists() async throws -> [ReminderList] {
    try await ensureAccess()
    let lists = try await store.lists()
    let incomplete = try await store.reminders(inLists: nil, completed: false)
    var counts: [String: (Int, Int)] = [:]
    for reminder in incomplete {
      var entry = counts[reminder.listID] ?? (0, 0)
      entry.0 += 1
      if clock.isOverdueForListCount(reminder) { entry.1 += 1 }
      counts[reminder.listID] = entry
    }
    return lists.map { list in
      let (count, overdue) = counts[list.id] ?? (0, 0)
      return ReminderList(id: list.id, title: list.title, reminderCount: count, overdueCount: overdue)
    }
    .sorted { $0.title < $1.title }
  }

  /// Reminders in one list (or all lists), selected by `filter` (helper `get-reminders`).
  public func getReminders(listID: String?, filter: ReminderFilter) async throws -> [Reminder] {
    try await ensureAccess()
    let lists = listID.map { [$0] }
    switch filter {
    case .completed:
      return try await store.reminders(inLists: lists, completed: true)
    case .all:
      let incomplete = try await store.reminders(inLists: lists, completed: false)
      return incomplete + (try await store.reminders(inLists: lists, completed: true))
    default:
      return try await store.reminders(inLists: lists, completed: false).filter { clock.matches($0, filter) }
    }
  }

  /// Incomplete reminders whose title or notes contain `query` (helper `search`).
  public func searchReminders(_ query: String) async throws -> [Reminder] {
    try await ensureAccess()
    return try await store.reminders(inLists: nil, completed: false).filter { reminderMatchesSearch($0, query: query) }
  }

  // MARK: Resolution (resolve.ts, lookup.ts)

  /// Resolve a user-typed list name with fuzzy matching.
  public func resolveList(_ query: String) async throws -> ReminderList {
    let lists = try await listLists()
    return try fuzzyFind(query, in: lists, name: \.title, itemType: "list")
  }

  /// Find a reminder in a list by title (or `--id` prefix), searching incomplete and completed reminders.
  public func findReminderByTitle(_ list: ReminderList, title: String, id: String? = nil) async throws -> Reminder {
    let reminders = try await getReminders(listID: list.id, filter: .all)
    return try findReminder(in: reminders, listName: list.title, title: title, id: id)
  }
}

// MARK: - Commands

extension CommandContext {
  /// `remi lists`
  public func lists() async throws {
    output.lists(try await listLists())
  }

  /// `remi list <name> [--include-completed]`. remi accepts `--section` here but doesn't filter by it.
  public func list(_ name: String, includeCompleted: Bool) async throws {
    let list = try await resolveList(name)
    let reminders = try await getReminders(listID: list.id, filter: includeCompleted ? .all : .incomplete)
    // Section enrichment (remi's ReminderKit + database lookup) lands with the sections layer.
    output.reminders(
      reminders, listName: list.title, options: .init(context: .list, sortByDate: true, groupBySections: true))
  }

  /// `remi today`
  public func today() async throws {
    let reminders = try await getReminders(listID: nil, filter: .today)
    output.reminders(
      reminders, listName: "Due Today", options: .init(context: .today, showList: true, sortByDate: true))
  }

  /// `remi overdue`
  public func overdue() async throws {
    let reminders = try await getReminders(listID: nil, filter: .overdue)
    output.reminders(
      reminders, listName: "Overdue", options: .init(context: .overdue, showList: true, sortByDate: true))
  }

  /// `remi upcoming [--days <n>]` (`--days` is parsed like JavaScript's parseInt).
  public func upcoming(days daysText: String?) async throws {
    let days = daysText.map(jsParseInt) ?? 7
    let reminders = try await getReminders(listID: nil, filter: .upcoming(days: days ?? 7))
    output.reminders(
      reminders, listName: "Due in next \(days.map(String.init) ?? "NaN") days",
      options: .init(context: .upcoming, showList: true, sortByDate: true))
  }

  /// `remi search <query>`
  public func search(_ query: String) async throws {
    let reminders = try await searchReminders(query)
    output.reminders(
      reminders, listName: "Search: \"\(query)\"", options: .init(context: .search, showList: true, sortByDate: true))
  }

  /// `remi add <list> <title> [--due] [--priority] [--notes] [--repeat]`
  public func add(
    list listQuery: String, title: String, section: String? = nil, due: String? = nil, priority: String? = "none",
    notes: String? = nil, repeat repeatRule: String? = nil
  ) async throws {
    if section != nil {
      throw RemiCommandError(
        .reminderKitUnavailable, "Sections are not supported yet in the Swift port",
        suggestion: "Add the reminder without --section for now")
    }
    let list = try await resolveList(listQuery)
    let dueDay = try due.map { try dueDayArgument(parseDate($0, now: clock.now, timeZone: clock.timeZone)) }
    let recurrence = try repeatRule.map { try RecurrenceRule(parseRepeat($0)) }

    let id = try await store.createReminder(
      NewReminder(
        title: title, listID: list.id, due: dueDay, notes: notes, priority: priority.map(priorityArgument),
        recurrence: recurrence))

    var message = "Added \"\(title)\" to \"\(list.title)\""
    if let repeatRule { message += " (repeats \(repeatRule))" }
    output.message(message, data: [("id", .string(id))])
  }

  /// `remi complete <list> <title> [--id]`
  public func complete(list listQuery: String, title: String, id: String? = nil) async throws {
    let list = try await resolveList(listQuery)
    let reminder = try await findReminderByTitle(list, title: title, id: id)
    _ = try await store.completeReminder(id: reminder.id)
    output.message("Completed \"\(reminder.title)\" in \"\(list.title)\"")
  }

  /// `remi update <list> <title> [--title] [--due] [--clear-due] [--priority] [--notes]`
  public func update(
    list listQuery: String, title: String, newTitle: String? = nil, due: String? = nil, clearDue: Bool = false,
    priority: String? = nil, notes: String? = nil
  ) async throws {
    let list = try await resolveList(listQuery)
    let reminder = try await findReminderByTitle(list, title: title)
    let dueDay = try due.map { try dueDayArgument(parseDate($0, now: clock.now, timeZone: clock.timeZone)) }
    _ = try await store.editReminder(
      id: reminder.id,
      ReminderEdit(
        title: newTitle, due: dueDay, clearDue: clearDue, notes: notes, priority: priority.map(priorityArgument)))
    output.message("Updated \"\(reminder.title)\" in \"\(list.title)\"")
  }

  /// `remi delete <list> <title> [--id] --confirm` (`--confirm` not needed in JSON mode)
  public func delete(list listQuery: String, title: String, id: String? = nil, confirm: Bool) async throws {
    if !confirm && !output.jsonMode {
      throw RemiCommandError(
        .invalidArgument, "Deletion requires --confirm flag",
        suggestion: "Run: remi delete \"\(listQuery)\" \"\(title)\" --confirm")
    }
    let list = try await resolveList(listQuery)
    let reminder = try await findReminderByTitle(list, title: title, id: id)
    _ = try await store.deleteReminder(id: reminder.id)
    output.message("Deleted \"\(reminder.title)\" from \"\(list.title)\"")
  }

  /// `remi create-list <name>` (idempotent: an existing list with that exact title is reused)
  public func createList(_ name: String) async throws {
    try await ensureAccess()
    let existing = try await store.lists().first { $0.title == name }
    let id: String
    if let existing {
      id = existing.id
    } else {
      id = try await store.createList(title: name)
    }
    output.message("Created list \"\(name)\"", data: [("id", .string(id))])
  }

  /// `remi delete-list <name> --confirm` (`--confirm` not needed in JSON mode)
  public func deleteList(_ name: String, confirm: Bool) async throws {
    if !confirm && !output.jsonMode {
      throw RemiCommandError(
        .invalidArgument, "List deletion requires --confirm flag",
        suggestion: "Run: remi delete-list \"\(name)\" --confirm")
    }
    let list = try await resolveList(name)
    try await store.deleteList(id: list.id)
    output.message("Deleted list \"\(list.title)\"")
  }
}

// MARK: - Argument helpers

/// remi passes `--priority` straight to the helper, which treats anything unknown as "none".
func priorityArgument(_ text: String) -> Priority {
  Priority(rawValue: text) ?? .none
}

/// The helper silently ignores due dates its DateFormatter can't read; the port reports them instead.
func dueDayArgument(_ text: String) throws(RemiCommandError) -> DueDay {
  guard let day = DueDay(text) else {
    throw RemiCommandError(
      .invalidArgument, "Invalid date \"\(text)\"", suggestion: "Use a real calendar date (YYYY-MM-DD)")
  }
  return day
}

/// JavaScript's `Number.parseInt(text, 10)`; nil stands for NaN.
func jsParseInt(_ text: String) -> Int? {
  var scalars = Substring(text.jsTrimmed).unicodeScalars[...]
  var sign = 1
  if let first = scalars.first, first == "-" || first == "+" {
    if first == "-" { sign = -1 }
    scalars = scalars.dropFirst()
  }
  let digits = scalars.prefix { ("0"..."9").contains($0) }
  guard !digits.isEmpty else { return nil }
  return (Int(String(String.UnicodeScalarView(digits))) ?? Int.max) * sign
}
