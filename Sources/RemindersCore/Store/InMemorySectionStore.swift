import Foundation

/// Sections and memberships in memory, for tests and previews. It keeps the stored strings exactly as written and
/// enforces ``SectionStore/replaceMemberships(of:with:ifUnchangedFrom:)``'s compare-and-swap.
public actor InMemorySectionStore: SectionStore {
  /// Sections by list identifier.
  public private(set) var sectionsByList: [String: [Section]]
  /// Stored membership data by list identifier.
  public private(set) var membershipsByList: [String: StoredMemberships]
  /// How many times memberships were replaced, so tests can tell a no-op from a write.
  public private(set) var writeCount = 0
  /// Called before each replacement checks `expected`, to simulate another writer getting in first.
  private var interference: (@Sendable (String) -> StoredMemberships?)?

  public init(sections: [String: [Section]] = [:], memberships: [String: StoredMemberships] = [:]) {
    sectionsByList = sections
    membershipsByList = memberships
  }

  /// Simulates another writer: before the next replacements, the list's data becomes what `change` returns.
  public func interfere(_ change: @escaping @Sendable (String) -> StoredMemberships?) {
    interference = change
  }

  public func sections(in list: ReminderList) -> [Section] {
    (sectionsByList[list.id] ?? []).sorted { $0.sortOrder < $1.sortOrder }
  }

  public func createSection(named name: String, in list: ReminderList) -> Section {
    let existing = sectionsByList[list.id] ?? []
    let section = Section(
      id: UUID().uuidString, displayName: name, listName: list.title,
      sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1)
    sectionsByList[list.id] = existing + [section]
    return section
  }

  public func deleteSection(_ section: Section, in list: ReminderList) throws(RemindersError) {
    guard let existing = sectionsByList[list.id], existing.contains(where: { $0.id == section.id }) else {
      throw RemindersError(.sectionNotFound, "Section '\(section.id)' not found")
    }
    sectionsByList[list.id] = existing.filter { $0.id != section.id }
  }

  public func memberships(of list: ReminderList) -> StoredMemberships {
    membershipsByList[list.id] ?? StoredMemberships()
  }

  public func replaceMemberships(
    of list: ReminderList, with replacement: StoredMemberships, ifUnchangedFrom expected: StoredMemberships
  ) throws(RemindersError) {
    if let change = interference?(list.id) { membershipsByList[list.id] = change }
    guard memberships(of: list) == expected else { throw .membershipConflict }
    membershipsByList[list.id] = replacement
    writeCount += 1
  }
}
