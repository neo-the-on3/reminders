import RemindersCore

/// Sections on macOS: read from Reminders' database, created and deleted through ReminderKit.
///
/// Reads come from the database because it also holds the membership data, which ReminderKit doesn't expose;
/// creating and deleting go through ReminderKit so iCloud syncs them. Both need the database's view of the list,
/// so both need Full Disk Access.
public struct AppleSectionStore: SectionStore {
  private let database: any SectionStore
  private let reminderKit: any ReminderKitBridge

  public init(database: any SectionStore, reminderKit: any ReminderKitBridge) {
    self.database = database
    self.reminderKit = reminderKit
  }

  public func sections(in list: ReminderList) async throws(RemindersError) -> [Section] {
    try await database.sections(in: list)
  }

  public func createSection(named name: String, in list: ReminderList) async throws(RemindersError) -> Section {
    let created = try reminderKit.createSection(named: name, in: list)
    // The database may not have it yet; then it goes after the sections that are there.
    let saved = (try? await database.sections(in: list)) ?? []
    return saved.first { $0.id == created.id }
      ?? Section(id: created.id, displayName: created.displayName, listName: list.title, sortOrder: saved.count)
  }

  public func deleteSection(_ section: Section, in list: ReminderList) throws(RemindersError) {
    try reminderKit.deleteSection(id: section.id, in: list)
  }

  public func memberships(of list: ReminderList) async throws(RemindersError) -> StoredMemberships {
    try await database.memberships(of: list)
  }

  public func replaceMemberships(
    of list: ReminderList, with new: StoredMemberships, ifUnchangedFrom old: StoredMemberships
  ) async throws(RemindersError) {
    try await database.replaceMemberships(of: list, with: new, ifUnchangedFrom: old)
  }
}
