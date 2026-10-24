import Foundation

/// Sections and memberships in memory, for tests and previews. Membership data comes back exactly as given until a
/// reminder is assigned; then it's rewritten with that reminder in its new section.
public actor InMemorySectionStore: SectionStore {
  /// Sections by list identifier.
  public private(set) var sectionsByList: [String: [Section]]
  /// Stored membership data by list identifier.
  public private(set) var membershipsByList: [String: StoredMemberships]
  /// Every assignment made, in order, as (list, reminder, section) identifiers.
  public private(set) var assignments: [(listID: String, reminderID: String, sectionID: String)] = []
  /// When set, the next assignment fails with it.
  private var assignmentFailure: RemindersError?
  /// Manual reminder orders by list identifier.
  public private(set) var manualOrders: [String: [String]]

  public init(
    sections: [String: [Section]] = [:], memberships: [String: StoredMemberships] = [:],
    manualOrders: [String: [String]] = [:]
  ) {
    sectionsByList = sections
    membershipsByList = memberships
    self.manualOrders = manualOrders
  }

  public func manualReminderOrder(of list: ReminderList) -> [String]? { manualOrders[list.id] }

  /// Makes the next ``assign(reminderID:to:in:)`` fail with `error`.
  public func failNextAssignment(with error: RemindersError) {
    assignmentFailure = error
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

  /// The list's membership data as given (or as rewritten by assignments), whichever reminders are asked about.
  public func memberships(of list: ReminderList, reminderIDs: [String] = []) -> StoredMemberships {
    membershipsByList[list.id] ?? StoredMemberships()
  }

  public func assign(reminderID: String, to section: Section, in list: ReminderList) throws(RemindersError) {
    if let failure = assignmentFailure {
      assignmentFailure = nil
      throw failure
    }
    guard sections(in: list).contains(where: { $0.id == section.id }) else {
      throw RemindersError(.sectionNotFound, "Section '\(section.id)' not found")
    }
    let current = (try? SectionMemberships(storedData: memberships(of: list).data))?.entries ?? []
    let entries =
      current.filter { $0.reminderID != reminderID }
      + [SectionMemberships.Entry(reminderID: reminderID, sectionID: section.id)]
    let items = entries.map { #"{"memberID":"\#($0.reminderID)","groupID":"\#($0.sectionID)"}"# }
    membershipsByList[list.id] = StoredMemberships(
      data: #"{"minimumSupportedVersion":20230430,"memberships":["# + items.joined(separator: ",") + "]}")
    assignments.append((list.id, reminderID, section.id))
  }
}
