import Foundation

/// Sections: the commands, and the one place membership data is edited.
///
/// Every membership change reads the stored data, edits it with ``SectionMemberships`` (which keeps unknown
/// fields and formatting), records the change in the list's ``ResolutionTokenMap`` so iCloud sync pushes it,
/// recomputes the checksum, and writes all three back with a compare-and-swap. When Reminders changed the data in
/// between, the edit starts again from the new data.
extension RemindersService {
  /// How many times a membership edit is retried when Reminders changes the data underneath it.
  static let membershipAttempts = 3

  // MARK: Commands

  /// `reminders sections <list>`: the list's sections, with how many incomplete reminders each holds.
  public func sections(ofList name: String) async throws(RemindersError) -> SectionListing {
    let list = try await lists().resolve(name)
    let layout = try await sectionLayout(of: list)
    var counts = Dictionary(layout.sections.map { ($0.displayName, 0) }, uniquingKeysWith: { first, _ in first })
    for reminder in try await store.reminders(inLists: [list.id], .incomplete) {
      guard let sectionID = layout.sectionID(of: reminder),
        let section = layout.sections.first(where: { $0.id == sectionID })
      else { continue }
      counts[section.displayName, default: 0] += 1
    }
    return SectionListing(layout.sections, listName: list.title, counts: counts)
  }

  /// `reminders create-section`. A section with exactly that name is reused rather than duplicated.
  public func createSection(named name: String, inList listName: String) async throws(RemindersError)
    -> Confirmation
  {
    let list = try await lists().resolve(listName)
    let section: Section
    if let existing = try await sectionStore.sections(in: list).first(where: { $0.displayName == name }) {
      section = existing
    } else {
      section = try await sectionStore.createSection(named: name, in: list)
    }
    return Confirmation("Created section \"\(name)\" in \"\(list.title)\"", id: section.id)
  }

  /// `reminders delete-section`. Its reminders stay in the list, outside any section.
  public func deleteSection(named name: String, inList listName: String) async throws(RemindersError)
    -> Confirmation
  {
    let list = try await lists().resolve(listName)
    let section = try await sectionStore.sections(in: list).resolve(name)
    try await sectionStore.deleteSection(section, in: list)
    try await editMemberships(of: list) { $0.removeAll(inSection: section.id) }
    return Confirmation("Deleted section \"\(section.displayName)\" from \"\(list.title)\"")
  }

  /// `reminders move`: puts a reminder in a section of its list, taking it out of any other.
  public func move(_ reference: ReminderReference, toSection name: String) async throws(RemindersError)
    -> Confirmation
  {
    let (list, reminder) = try await find(reference)
    let section = try await sectionStore.sections(in: list).resolve(name)
    let moved = try await editMemberships(of: list) {
      $0.assign(Self.memberID(reminder.id), to: section.id, at: clock.now)
    }
    return Confirmation(
      moved
        ? "Moved \"\(reminder.title)\" to section \"\(section.displayName)\" in \"\(list.title)\""
        : "\"\(reminder.title)\" is already in section \"\(section.displayName)\" in \"\(list.title)\"")
  }

  // MARK: Membership data

  /// The list's sections and which reminder is in which.
  func sectionLayout(of list: ReminderList) async throws(RemindersError) -> SectionLayout {
    let sections = try await sectionStore.sections(in: list)
    let memberships = try SectionMemberships(storedData: try await sectionStore.memberships(of: list).data)
    return SectionLayout(sections: sections, memberships: memberships)
  }

  /// Applies `edit` to the list's memberships and writes the result with a fresh checksum and token map. Returns
  /// false, writing nothing, when `edit` changed nothing.
  @discardableResult
  func editMemberships(of list: ReminderList, _ edit: (inout SectionMemberships) -> Bool)
    async throws(RemindersError) -> Bool
  {
    for _ in 0..<Self.membershipAttempts {
      let stored = try await sectionStore.memberships(of: list)
      guard !SectionMemberships.isCorrupt(stored) else {
        throw RemindersError(
          .storeFailure, "The section data of \"\(list.title)\" doesn't match its checksum, so it was left alone",
          suggestion: "Open \"\(list.title)\" in the Reminders app, then try again")
      }
      var memberships = try SectionMemberships(storedData: stored.data)
      guard edit(&memberships) else { return false }
      var tokens = ResolutionTokenMap(storedData: stored.tokenMap)
      tokens.recordMembershipChange(at: clock.now, newReplicaID: UUID().uuidString)
      let replacement = StoredMemberships(
        data: memberships.storedData, checksum: memberships.checksum, tokenMap: tokens.storedData)
      do {
        try await sectionStore.replaceMemberships(of: list, with: replacement, ifUnchangedFrom: stored)
        return true
      } catch  where error.code == .storeConflict {
        continue
      }
    }
    throw .membershipConflict
  }

  /// A reminder's identifier as membership data spells it: an upper-case UUID.
  static func memberID(_ reminderID: String) -> String { reminderID.uppercased() }
}

/// A list's sections together with which reminder is in which.
struct SectionLayout: Sendable {
  let sections: [Section]
  /// Section identifier by member identifier, for sections that still exist.
  private let sectionsByReminder: [String: String]

  init(sections: [Section], memberships: SectionMemberships) {
    self.sections = sections
    let existing = Set(sections.map(\.id))
    sectionsByReminder = memberships.sectionsByReminder.filter { existing.contains($0.value) }
  }

  /// The section `reminder` is in, if that section still exists.
  func sectionID(of reminder: Reminder) -> String? {
    sectionsByReminder[RemindersService.memberID(reminder.id)]
  }

  /// `reminders` with ``Reminder/section`` set to their section's name.
  func tagging(_ reminders: [Reminder]) -> [Reminder] {
    reminders.map { reminder in
      var reminder = reminder
      if let id = sectionID(of: reminder) { reminder.section = sections.first { $0.id == id }?.displayName }
      return reminder
    }
  }

}
