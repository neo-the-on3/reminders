#if canImport(EventKit)
  import EventKit
  import Foundation
  import RemindersCore

  /// Apple Reminders through EventKit.
  ///
  /// An actor so the event store is only ever touched serially. `EKReminder`s and `EKCalendar`s never leave it:
  /// fetches convert them to ``Reminder`` values in EventKit's callback, and changes look items up again by
  /// identifier.
  public actor EventKitReminderStore: ReminderStore {
    private let store = EKEventStore()

    public init() {}

    // MARK: Access

    public func accessStatus() -> ReminderAccess {
      Self.access(EKEventStore.authorizationStatus(for: .reminder))
    }

    public func requestFullAccess() async throws(RemindersError) -> ReminderAccess {
      guard accessStatus() == .notDetermined else { return accessStatus() }
      let failure: String? = await withCheckedContinuation { continuation in
        store.requestFullAccessToReminders { @Sendable _, error in
          continuation.resume(returning: error.map { $0.localizedDescription })
        }
      }
      if let failure { throw RemindersError(.permissionDenied, "Could not request Reminders access: \(failure)") }
      return accessStatus()
    }

    // MARK: Reading

    public func lists() -> [ReminderList] {
      store.calendars(for: .reminder).map { ReminderList(id: $0.calendarIdentifier, title: $0.title) }
    }

    public func reminders(inLists listIDs: [String]?, _ filter: CompletionFilter) async throws(RemindersError)
      -> [Reminder]
    {
      var calendars: [EKCalendar]?
      if let listIDs {
        calendars = []
        for id in listIDs { calendars?.append(try calendar(id: id)) }
      }
      let predicate =
        switch filter {
        case .incomplete:
          store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        case .completed:
          store.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: calendars)
        }
      return await withCheckedContinuation { continuation in
        store.fetchReminders(matching: predicate) { @Sendable items in
          continuation.resume(returning: (items ?? []).map(Self.reminder(from:)))
        }
      }
    }

    // MARK: Reminder changes

    public func createReminder(_ draft: ReminderDraft) throws(RemindersError) -> String {
      let reminder = EKReminder(eventStore: store)
      reminder.calendar = try calendar(id: draft.listID)
      reminder.title = draft.title
      reminder.notes = draft.notes
      reminder.priority = draft.priority.eventKitValue
      reminder.dueDateComponents = draft.dueDate?.dateComponents
      if let recurrence = draft.recurrence { reminder.addRecurrenceRule(Self.rule(for: recurrence)) }
      try save(reminder, failure: "Save failed")
      return reminder.calendarItemIdentifier
    }

    public func updateReminder(id: String, _ changes: ReminderChanges) throws(RemindersError) {
      let reminder = try reminder(id: id)
      if let title = changes.title { reminder.title = title }
      if let notes = changes.notes { reminder.notes = notes }
      if let priority = changes.priority { reminder.priority = priority.eventKitValue }
      switch changes.dueDate {
      case .set(let day): reminder.dueDateComponents = day.dateComponents
      case .remove: reminder.dueDateComponents = nil
      case nil: break
      }
      try save(reminder, failure: "Save failed")
    }

    public func completeReminder(id: String) throws(RemindersError) {
      let reminder = try reminder(id: id)
      reminder.isCompleted = true
      try save(reminder, failure: "Complete failed")
    }

    public func deleteReminder(id: String) throws(RemindersError) {
      let reminder = try reminder(id: id)
      do {
        try store.remove(reminder, commit: true)
      } catch {
        throw RemindersError(.storeFailure, "Delete failed: \(error.localizedDescription)")
      }
    }

    // MARK: List changes

    public func createList(title: String) throws(RemindersError) -> String {
      guard let source = store.defaultCalendarForNewReminders()?.source else {
        throw RemindersError(.storeFailure, "No account to create the list in")
      }
      let calendar = EKCalendar(for: .reminder, eventStore: store)
      calendar.title = title
      calendar.source = source
      do {
        try store.saveCalendar(calendar, commit: true)
      } catch {
        throw RemindersError(.storeFailure, "Create list failed: \(error.localizedDescription)")
      }
      return calendar.calendarIdentifier
    }

    public func deleteList(id: String) throws(RemindersError) {
      let calendar = try calendar(id: id)
      do {
        try store.removeCalendar(calendar, commit: true)
      } catch {
        throw RemindersError(.storeFailure, "Delete list failed: \(error.localizedDescription)")
      }
    }

    // MARK: Lookups

    private func calendar(id: String) throws(RemindersError) -> EKCalendar {
      guard let calendar = store.calendar(withIdentifier: id), calendar.allowedEntityTypes.contains(.reminder) else {
        throw RemindersError(.listNotFound, "List '\(id)' not found")
      }
      return calendar
    }

    private func reminder(id: String) throws(RemindersError) -> EKReminder {
      guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
        throw RemindersError(.reminderNotFound, "Reminder '\(id)' not found")
      }
      return reminder
    }

    private func save(_ reminder: EKReminder, failure: String) throws(RemindersError) {
      do {
        try store.save(reminder, commit: true)
      } catch {
        throw RemindersError(.storeFailure, "\(failure): \(error.localizedDescription)")
      }
    }

    // MARK: Mapping

    private static func access(_ status: EKAuthorizationStatus) -> ReminderAccess {
      switch status {
      case .fullAccess: .fullAccess
      case .writeOnly: .writeOnly
      case .denied: .denied
      case .restricted: .restricted
      case .notDetermined: .notDetermined
      @unknown default: .denied
      }
    }

    private static func reminder(from item: EKReminder) -> Reminder {
      let due = item.dueDateComponents.flatMap { components -> CalendarDay? in
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        return CalendarDay(year: year, month: month, day: day)
      }
      let rules = item.recurrenceRules ?? []
      return Reminder(
        id: item.calendarItemIdentifier, title: item.title ?? "", isCompleted: item.isCompleted,
        listID: item.calendar?.calendarIdentifier ?? "", listName: item.calendar?.title ?? "",
        priority: Priority(eventKitValue: item.priority), dueDate: due, completionDate: item.completionDate,
        notes: item.notes, recurrence: rules.first.flatMap(recurrence(from:)), isRecurring: !rules.isEmpty)
    }

    private static func recurrence(from rule: EKRecurrenceRule) -> Recurrence? {
      let frequency: Recurrence.Frequency
      switch rule.frequency {
      case .daily: frequency = .daily
      case .weekly: frequency = .weekly
      case .monthly: frequency = .monthly
      case .yearly: frequency = .yearly
      @unknown default: return nil
      }
      let weekdays = (rule.daysOfTheWeek ?? []).compactMap { Recurrence.Weekday(rawValue: $0.dayOfTheWeek.rawValue) }
      return Recurrence(frequency, interval: rule.interval, on: weekdays)
    }

    private static func rule(for recurrence: Recurrence) -> EKRecurrenceRule {
      let frequency: EKRecurrenceFrequency =
        switch recurrence.frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
      let days = recurrence.weekdays.compactMap { EKWeekday(rawValue: $0.rawValue).map { EKRecurrenceDayOfWeek($0) } }
      let end = recurrence.end.flatMap { $0.startDate(in: .current) }.map { EKRecurrenceEnd(end: $0) }
      return EKRecurrenceRule(
        recurrenceWith: frequency, interval: recurrence.interval, daysOfTheWeek: days.isEmpty ? nil : days,
        daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil,
        end: end)
    }
  }
#endif
