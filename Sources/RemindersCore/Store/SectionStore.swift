/// Where a list's sections, and which reminder is in which section, are kept.
///
/// EventKit has no sections. Reminders keeps the sections as their own records, and the memberships as JSON on the
/// list (see ``SectionMemberships``). Changes go through Reminders itself, never by writing its data directly, so
/// Reminders keeps the membership data, its checksum and iCloud sync consistent.
public protocol SectionStore: Sendable {
  /// The list's sections, in display order.
  func sections(in list: ReminderList) async throws(RemindersError) -> [Section]
  func createSection(named name: String, in list: ReminderList) async throws(RemindersError) -> Section
  func deleteSection(_ section: Section, in list: ReminderList) async throws(RemindersError)

  /// The list's membership data as stored.
  func memberships(of list: ReminderList) async throws(RemindersError) -> StoredMemberships
  /// Puts a reminder in one of the list's sections, taking it out of any other.
  /// - Parameter reminderID: The reminder's identifier as an upper-case dashed UUID.
  func assign(reminderID: String, to section: Section, in list: ReminderList) async throws(RemindersError)
}

/// A list's section-membership data exactly as Reminders stores it. Nil when the list has none (NULL).
public struct StoredMemberships: Hashable, Sendable {
  /// The memberships JSON (`ZMEMBERSHIPSOFREMINDERSINSECTIONSASDATA`).
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
  public func memberships(of list: ReminderList) throws(RemindersError) -> StoredMemberships {
    throw Self.unavailable
  }
  public func assign(reminderID: String, to section: Section, in list: ReminderList) throws(RemindersError) {
    throw Self.unavailable
  }
}
