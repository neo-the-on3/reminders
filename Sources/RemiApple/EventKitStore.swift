// EventKit implementation of ReminderStore, ported from remi src/swift/reminders-helper.swift
// (MIT, Matthew O'Riordan). Same lookups and mappings as the helper; errors are RemiCommandErrors.

#if canImport(EventKit)
  import EventKit
  import Foundation
  import RemiCore

  /// Apple Reminders through EventKit.
  ///
  /// `EKReminder` objects never leave this type: fetch callbacks convert them to ``Reminder`` values, and
  /// mutations re-fetch by identifier, as remi's helper does.
  final class EventKitStore: ReminderStore, @unchecked Sendable {
    private let store = EKEventStore()

    // MARK: Access

    func requestAccess() async throws -> ReminderAccess {
      if accessStatus() == .granted { return .granted }
      do {
        _ = try await store.requestFullAccessToReminders()
      } catch {
        return .denied
      }
      return accessStatus()
    }

    func accessStatus() -> ReminderAccess {
      switch EKEventStore.authorizationStatus(for: .reminder) {
      case .fullAccess: return .granted
      case .writeOnly: return .writeOnly
      case .denied: return .denied
      case .restricted: return .restricted
      case .notDetermined: return .notDetermined
      @unknown default: return .denied
      }
    }

    // MARK: Reading

    func lists() async throws -> [StoreList] {
      store.calendars(for: .reminder).map { StoreList(id: $0.calendarIdentifier, title: $0.title) }
    }

    func reminders(inLists listIDs: [String]?, completed: Bool) async throws -> [Reminder] {
      let calendars = try listIDs.map { ids in try ids.map(calendar(id:)) }
      nonisolated(unsafe) let predicate =
        completed
        ? store.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: calendars)
        : store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
      return await withCheckedContinuation { continuation in
        store.fetchReminders(matching: predicate) { items in
          continuation.resume(returning: (items ?? []).map(Self.reminder(from:)))
        }
      }
    }

    // MARK: Writing

    func createReminder(_ new: NewReminder) async throws -> String {
      let reminder = EKReminder(eventStore: store)
      reminder.title = new.title
      reminder.calendar = try calendar(id: new.listID)
      if let notes = new.notes { reminder.notes = notes }
      if let priority = new.priority { reminder.priority = eventKitPriority(priority) }
      if let due = new.due { reminder.dueDateComponents = Self.components(due) }
      if let rule = new.recurrence { reminder.addRecurrenceRule(Self.recurrenceRule(rule)) }
      do {
        try store.save(reminder, commit: true)
      } catch {
        throw RemiCommandError(.swiftExecutionFailed, "Save failed: \(error.localizedDescription)")
      }
      return reminder.calendarItemIdentifier
    }

    func editReminder(id: String, _ edit: ReminderEdit) async throws -> String {
      try await withReminder(id: id, includeCompleted: false, failure: "Save failed") { store, reminder in
        if let title = edit.title { reminder.title = title }
        if let notes = edit.notes { reminder.notes = notes }
        if let priority = edit.priority { reminder.priority = eventKitPriority(priority) }
        if edit.clearDue {
          reminder.dueDateComponents = nil
        } else if let due = edit.due {
          reminder.dueDateComponents = Self.components(due)
        }
        try store.save(reminder, commit: true)
        return reminder.title ?? ""
      }
    }

    func completeReminder(id: String) async throws -> String {
      try await withReminder(id: id, includeCompleted: false, failure: "Complete failed") { store, reminder in
        reminder.isCompleted = true
        reminder.completionDate = Date()
        try store.save(reminder, commit: true)
        return reminder.title ?? ""
      }
    }

    func deleteReminder(id: String) async throws -> String {
      try await withReminder(id: id, includeCompleted: true, failure: "Delete failed") { store, reminder in
        let title = reminder.title ?? ""
        try store.remove(reminder, commit: true)
        return title
      }
    }

    func createList(title: String) async throws -> String {
      guard let source = store.defaultCalendarForNewReminders()?.source else {
        throw RemiCommandError(.swiftExecutionFailed, "No reminder source available")
      }
      let calendar = EKCalendar(for: .reminder, eventStore: store)
      calendar.title = title
      calendar.source = source
      do {
        try store.saveCalendar(calendar, commit: true)
      } catch {
        throw RemiCommandError(.swiftExecutionFailed, "Create list failed: \(error.localizedDescription)")
      }
      return calendar.calendarIdentifier
    }

    func deleteList(id: String) async throws {
      let calendar = try calendar(id: id)
      do {
        try store.removeCalendar(calendar, commit: true)
      } catch {
        throw RemiCommandError(.swiftExecutionFailed, "Delete list failed: \(error.localizedDescription)")
      }
    }

    // MARK: Helpers

    private func calendar(id: String) throws(RemiCommandError) -> EKCalendar {
      guard let calendar = store.calendar(withIdentifier: id), calendar.allowedEntityTypes.contains(.reminder) else {
        throw RemiCommandError(.listNotFound, "List '\(id)' not found")
      }
      return calendar
    }

    /// Find a reminder by (case-insensitive) identifier prefix, like the helper, and act on it inside the
    /// fetch callback so the `EKReminder` never crosses threads.
    private func withReminder(
      id: String, includeCompleted: Bool, failure: String,
      _ body: @escaping @Sendable (EKEventStore, EKReminder) throws -> String
    ) async throws -> String {
      nonisolated(unsafe) let store = self.store
      let predicates =
        [store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)]
        + (includeCompleted
          ? [store.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: nil)] : [])
      let prefix = id.uppercased()
      for predicate in predicates {
        let result: Result<String, RemiCommandError>? = await withCheckedContinuation { continuation in
          store.fetchReminders(matching: predicate) { items in
            guard
              let reminder = (items ?? []).first(where: { $0.calendarItemIdentifier.uppercased().hasPrefix(prefix) })
            else {
              continuation.resume(returning: nil)
              return
            }
            do {
              continuation.resume(returning: .success(try body(store, reminder)))
            } catch {
              continuation.resume(
                returning: .failure(
                  RemiCommandError(.swiftExecutionFailed, "\(failure): \(error.localizedDescription)")))
            }
          }
        }
        if let result { return try result.get() }
      }
      throw RemiCommandError(.reminderNotFound, "Reminder '\(id)' not found")
    }

    private static func components(_ day: DueDay) -> DateComponents {
      DateComponents(year: day.year, month: day.month, day: day.day)
    }

    private static func recurrenceRule(_ rule: RecurrenceRule) -> EKRecurrenceRule {
      let frequency: EKRecurrenceFrequency
      switch rule.frequency {
      case .daily: frequency = .daily
      case .weekly: frequency = .weekly
      case .monthly: frequency = .monthly
      case .yearly: frequency = .yearly
      }
      let days = rule.daysOfWeek.compactMap { EKWeekday(rawValue: $0).map { EKRecurrenceDayOfWeek($0) } }
      var end: EKRecurrenceEnd?
      if let endDay = rule.end, let date = Calendar.current.date(from: components(endDay)) {
        end = EKRecurrenceEnd(end: date)
      }
      return EKRecurrenceRule(
        recurrenceWith: frequency, interval: rule.interval, daysOfTheWeek: days.isEmpty ? nil : days,
        daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil,
        end: end)
    }

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime]
      return formatter
    }()

    /// The helper's `reminderToItem`.
    static func reminder(from item: EKReminder) -> Reminder {
      var dueDate: String?
      if let due = item.dueDateComponents, let year = due.year, let month = due.month, let day = due.day {
        dueDate = DueDay(year: year, month: month, day: day).string
      }
      var recurrence: String?
      if let rule = item.recurrenceRules?.first {
        let frequency: RecurrenceRule.Frequency
        switch rule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        @unknown default: frequency = .daily
        }
        let days = (rule.daysOfTheWeek ?? []).map { $0.dayOfTheWeek.rawValue }
        recurrence = describeRecurrence(frequency: frequency, interval: rule.interval, daysOfWeek: days)
      }
      return Reminder(
        id: item.calendarItemIdentifier, title: item.title ?? "", isCompleted: item.isCompleted,
        listID: item.calendar?.calendarIdentifier ?? "", listName: item.calendar?.title ?? "",
        priority: priority(fromEventKit: item.priority), dueDate: dueDate,
        completionDate: item.completionDate.map { isoFormatter.string(from: $0) }, notes: item.notes,
        isRecurring: !(item.recurrenceRules ?? []).isEmpty, recurrence: recurrence)
    }
  }
#endif
