/// Where a list's sections, and which reminder is in which section, are kept.
///
/// EventKit has no sections. Reminders keeps the sections as their own records, and the memberships as JSON on the
/// list (see ``SectionMemberships``). Reads and changes go through Reminders itself, never its data directly, so
/// Reminders keeps the membership data, its checksum and iCloud sync consistent.
public protocol SectionStore: Sendable {
  /// The list's sections, in display order.
  func sections(in list: ReminderList) async throws(RemindersError) -> [Section]
  func createSection(named name: String, in list: ReminderList) async throws(RemindersError) -> Section
  func deleteSection(_ section: Section, in list: ReminderList) async throws(RemindersError)

  /// The order the user arranged the list's reminders in, as reminder identifiers, when the list is sorted
  /// manually; nil when it isn't, or the order can't be read. Never fails: it only arranges what's shown.
  func manualReminderOrder(of list: ReminderList) async -> [String]?

  /// Which section each of `reminderIDs` (upper-case dashed UUIDs) is in, in Reminders' membership format.
  /// Reminders in no section may be left out.
  func memberships(of list: ReminderList, reminderIDs: [String]) async throws(RemindersError) -> StoredMemberships
  /// Puts a reminder in one of the list's sections, taking it out of any other.
  /// - Parameter reminderID: The reminder's identifier as an upper-case dashed UUID.
  func assign(reminderID: String, to section: Section, in list: ReminderList) async throws(RemindersError)
}

extension SectionStore {
  public func manualReminderOrder(of list: ReminderList) async -> [String]? { nil }
}

/// Section memberships in Reminders' own format: the JSON it keeps on a list and syncs through iCloud
/// (`MembershipsOfRemindersInSectionsAsData`). Nil when there are none.
public struct StoredMemberships: Hashable, Sendable {
  /// The memberships JSON.
  public var data: String?

  public init(data: String? = nil) {
    self.data = data
  }
}

/// The section store where sections aren't available: every call is `NOT_IMPLEMENTED`.
public struct NoSectionStore: SectionStore {
  public init() {}

  private static var unavailable: RemindersError { .notImplemented("Sections") }

  public func sections(in list: ReminderList) throws(RemindersError) -> [Section] { throw Self.unavailable }
  public func createSection(named name: String, in list: ReminderList) throws(RemindersError) -> Section {
    throw Self.unavailable
  }
  public func deleteSection(_ section: Section, in list: ReminderList) throws(RemindersError) {
    throw Self.unavailable
  }
  public func memberships(of list: ReminderList, reminderIDs: [String]) throws(RemindersError) -> StoredMemberships {
    throw Self.unavailable
  }
  public func assign(reminderID: String, to section: Section, in list: ReminderList) throws(RemindersError) {
    throw Self.unavailable
  }
}
