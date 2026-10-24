import Foundation

/// Sections: the commands.
///
/// Changes go through the section store, which on a Mac hands them to Reminders itself (ReminderKit). Nothing here
/// writes membership data, its checksum or the sync bookkeeping: Reminders does, the way the app does.
extension RemindersService {
  // MARK: Commands

  /// `reminders sections <list>`: the list's sections, with how many incomplete reminders each holds.
  public func sections(ofList name: String) async throws(RemindersError) -> SectionListing {
    let list = try await lists().resolve(name)
    let reminders = try await store.reminders(inLists: [list.id], .incomplete)
    let layout = try await sectionLayout(of: list, for: reminders)
    var counts = Dictionary(layout.sections.map { ($0.displayName, 0) }, uniquingKeysWith: { first, _ in first })
    for reminder in reminders {
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
  ///
  /// The list and section are resolved first, so a bad name deletes nothing. The section store takes the section's
  /// reminders out of it in the same save as the deletion.
  public func deleteSection(named name: String, inList listName: String) async throws(RemindersError)
    -> Confirmation
  {
    let list = try await lists().resolve(listName)
    let section = try await sectionStore.sections(in: list).resolve(name)
    try await sectionStore.deleteSection(section, in: list)
    return Confirmation("Deleted section \"\(section.displayName)\" from \"\(list.title)\"")
  }

  /// `reminders move`: puts a reminder in a section of its list, taking it out of any other.
  public func move(_ reference: ReminderReference, toSection name: String) async throws(RemindersError)
    -> Confirmation
  {
    let (list, reminder) = try await find(reference)
    let section = try await sectionStore.sections(in: list).resolve(name)
    let current = try? await sectionLayout(of: list, for: [reminder]).sectionID(of: reminder)
    let moved = current != section.id
    if moved { try await sectionStore.assign(reminderID: Self.memberID(reminder.id), to: section, in: list) }
    return Confirmation(
      moved
        ? "Moved \"\(reminder.title)\" to section \"\(section.displayName)\" in \"\(list.title)\""
        : "\"\(reminder.title)\" is already in section \"\(section.displayName)\" in \"\(list.title)\"")
  }

  // MARK: Membership data

  /// The list's sections and which of `reminders` is in which.
  func sectionLayout(of list: ReminderList, for reminders: [Reminder]) async throws(RemindersError) -> SectionLayout {
    let sections = try await sectionStore.sections(in: list)
    // A list without sections has no memberships worth asking about.
    guard !sections.isEmpty else { return SectionLayout(sections: [], memberships: SectionMemberships(entries: [])) }
    let stored = try await sectionStore.memberships(of: list, reminderIDs: reminders.map { Self.memberID($0.id) })
    let memberships = try SectionMemberships(storedData: stored.data)
    return SectionLayout(sections: sections, memberships: memberships)
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
