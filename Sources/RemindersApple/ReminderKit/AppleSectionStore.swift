import RemindersCore

/// Sections on macOS, through ReminderKit, with Reminders' database as the fallback for reads.
///
/// Creating, deleting and moving reminders between sections go through ReminderKit only, so Reminders writes the
/// data and its checksum and iCloud syncs them; nothing here writes the database. Reads go through ReminderKit too
/// when it exposes what's asked for, which needs no Full Disk Access. Where it can't answer (a part missing on this
/// macOS version, any error, or memberships it doesn't expose), they come from the database, which does need Full
/// Disk Access.
public struct AppleSectionStore: SectionStore {
  private let database: any SectionStore
  private let reminderKit: any ReminderKitBridge
  private let readsThroughReminderKit: Bool

  /// - Parameter readsThroughReminderKit: False to read only from the database, as before ReminderKit reads.
  public init(database: any SectionStore, reminderKit: any ReminderKitBridge, readsThroughReminderKit: Bool = true) {
    self.database = database
    self.reminderKit = reminderKit
    self.readsThroughReminderKit = readsThroughReminderKit
  }

  public func sections(in list: ReminderList) async throws(RemindersError) -> [Section] {
    if let sections = read({ () throws(RemindersError) in try reminderKit.sections(in: list) }) {
      return sections.enumerated().map { order, section in
        Section(id: section.id, displayName: section.displayName, listName: list.title, sortOrder: order)
      }
    }
    return try await database.sections(in: list)
  }

  public func createSection(named name: String, in list: ReminderList) async throws(RemindersError) -> Section {
    let created = try reminderKit.createSection(named: name, in: list)
    // The store may not list it yet; then it goes after the sections that are there.
    let saved = (try? await sections(in: list)) ?? []
    return saved.first { $0.id == created.id }
      ?? Section(id: created.id, displayName: created.displayName, listName: list.title, sortOrder: saved.count)
  }

  public func deleteSection(_ section: Section, in list: ReminderList) throws(RemindersError) {
    try reminderKit.deleteSection(id: section.id, in: list)
  }

  public func memberships(of list: ReminderList) async throws(RemindersError) -> StoredMemberships {
    if let stored = read({ () throws(RemindersError) in try reminderKit.memberships(in: list) }) {
      return stored
    }
    return try await database.memberships(of: list)
  }

  /// The list's manual reminder order from ReminderKit, or nil when it isn't sorted manually or ReminderKit
  /// doesn't say.
  public func manualReminderOrder(of list: ReminderList) async -> [String]? {
    read { () throws(RemindersError) in try reminderKit.manualReminderOrder(in: list) }
  }

  public func assign(reminderID: String, to section: Section, in list: ReminderList) throws(RemindersError) {
    try reminderKit.assign(reminderID: reminderID, toSectionID: section.id, in: list)
  }

  /// A ReminderKit read, or nil to fall back to the database: when reads through ReminderKit are off, or it
  /// fails in any way. Reads never change anything, so the database's answer (or error) is as good.
  private func read<T>(_ body: () throws(RemindersError) -> T?) -> T? {
    guard readsThroughReminderKit else { return nil }
    do throws(RemindersError) {
      return try body()
    } catch {
      return nil
    }
  }
}
