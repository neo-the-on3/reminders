import RemindersCore

/// Section changes through ReminderKit, the private framework the Reminders app itself uses.
///
/// EventKit can't create or delete sections, and writing them into the database directly wouldn't sync, so these
/// go through ReminderKit, which saves them the way the app does and lets iCloud carry them to other devices. The
/// framework is private: ``RuntimeReminderKit`` loads it when first needed and checks every class and method it
/// uses, so a macOS release that changes them fails with ``RemindersError/Code/reminderKitUnavailable`` rather than
/// crashing. Tests use a fake.
public protocol ReminderKitBridge: Sendable {
  /// The list's sections, in ReminderKit's order.
  func sections(in list: ReminderList) throws(RemindersError) -> [ReminderKitSection]
  /// Creates a section and returns it.
  func createSection(named name: String, in list: ReminderList) throws(RemindersError) -> ReminderKitSection
  /// Deletes the section with identifier `id`.
  func deleteSection(id: String, in list: ReminderList) throws(RemindersError)
  /// Puts the reminder with identifier `reminderID` in the section `sectionID` (both upper-case dashed UUIDs),
  /// taking it out of any other section.
  func assign(reminderID: String, toSectionID sectionID: String, in list: ReminderList) throws(RemindersError)
}

/// A section as ReminderKit reports it.
public struct ReminderKitSection: Hashable, Sendable {
  /// Upper-case dashed UUID, as in the database and the membership data.
  public var id: String
  public var displayName: String

  public init(id: String, displayName: String) {
    self.id = id
    self.displayName = displayName
  }
}

extension RemindersError {
  /// ReminderKit, or a part of it this tool relies on, isn't there.
  static func reminderKitUnavailable(_ missing: String) -> RemindersError {
    RemindersError(
      .reminderKitUnavailable, "ReminderKit can't change sections on this Mac: \(missing)",
      suggestion:
        "Sections can still be listed. This macOS version may have changed Reminders' private framework; "
        + "report it at \(ProductInfo.homepage)/issues with your macOS version")
  }

  /// A ReminderKit call returned an error.
  static func reminderKitFailed(_ action: String, _ detail: String) -> RemindersError {
    RemindersError(
      .storeFailure, "Reminders couldn't \(action): \(detail)",
      suggestion: "Check that the list still exists and that Reminders can sync, then try again")
  }
}
