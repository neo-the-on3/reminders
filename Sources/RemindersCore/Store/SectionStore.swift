/// Where a list's sections, and which reminder is in which section, are kept.
///
/// EventKit has no sections. Reminders keeps the sections as their own records, and the memberships as JSON on the
/// list (see ``SectionMemberships``), next to a SHA-512 checksum of that JSON and a resolution token map
/// (``ResolutionTokenMap``) that tells iCloud sync what changed. A store moves that data in and out unchanged;
/// ``RemindersService`` does the editing, so every store gets the same rules.
public protocol SectionStore: Sendable {
  /// The list's sections, in display order.
  func sections(in list: ReminderList) async throws(RemindersError) -> [Section]
  func createSection(named name: String, in list: ReminderList) async throws(RemindersError) -> Section
  func deleteSection(_ section: Section, in list: ReminderList) async throws(RemindersError)

  /// The list's membership data as stored.
  func memberships(of list: ReminderList) async throws(RemindersError) -> StoredMemberships
  /// Replaces the list's membership data, checksum and token map together, but only while they are still
  /// `expected`; otherwise throws `STORE_CONFLICT` and changes nothing.
  func replaceMemberships(
    of list: ReminderList, with replacement: StoredMemberships, ifUnchangedFrom expected: StoredMemberships
  ) async throws(RemindersError)
}

/// A list's section-membership data exactly as Reminders stores it. Nil fields are absent (NULL) in the store.
public struct StoredMemberships: Hashable, Sendable {
  /// The memberships JSON (`ZMEMBERSHIPSOFREMINDERSINSECTIONSASDATA`).
  public var data: String?
  /// Lower-case hex SHA-512 of `data` (`ZMEMBERSHIPSOFREMINDERSINSECTIONSCHECKSUM`).
  public var checksum: String?
  /// The resolution token map JSON (`ZRESOLUTIONTOKENMAP_V3_JSONDATA`).
  public var tokenMap: String?

  public init(data: String? = nil, checksum: String? = nil, tokenMap: String? = nil) {
    self.data = data
    self.checksum = checksum
    self.tokenMap = tokenMap
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
  public func replaceMemberships(
    of list: ReminderList, with replacement: StoredMemberships, ifUnchangedFrom expected: StoredMemberships
  ) throws(RemindersError) {
    throw Self.unavailable
  }
}
