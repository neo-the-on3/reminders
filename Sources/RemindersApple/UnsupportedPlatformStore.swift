import RemindersCore

/// The store on platforms without Apple Reminders: access is unavailable and every operation fails with
/// `UNSUPPORTED_PLATFORM`.
public struct UnsupportedPlatformStore: ReminderStore {
  public init() {}

  private static let error = RemindersError.unsupportedPlatform

  public func accessStatus() -> ReminderAccess { .unavailable }
  public func requestFullAccess() throws(RemindersError) -> ReminderAccess { throw Self.error }
  public func lists() throws(RemindersError) -> [ReminderList] { throw Self.error }
  public func reminders(inLists listIDs: [String]?, _ filter: CompletionFilter) throws(RemindersError) -> [Reminder] {
    throw Self.error
  }
  public func createReminder(_ draft: ReminderDraft) throws(RemindersError) -> String { throw Self.error }
  public func updateReminder(id: String, _ changes: ReminderChanges) throws(RemindersError) { throw Self.error }
  public func completeReminder(id: String) throws(RemindersError) { throw Self.error }
  public func deleteReminder(id: String) throws(RemindersError) { throw Self.error }
  public func createList(title: String) throws(RemindersError) -> String { throw Self.error }
  public func deleteList(id: String) throws(RemindersError) { throw Self.error }
}
