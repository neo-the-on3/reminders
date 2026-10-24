import Foundation
import RemindersCore

/// Sections through ReminderKit, the private framework the Reminders app itself uses.
///
/// EventKit has no sections, and writing them into the database directly wouldn't sync, so changes go through
/// ReminderKit, which saves them the way the app does and lets iCloud carry them to other devices. Reads go
/// through it too where it exposes what's needed, so they don't need Full Disk Access. The
/// framework is private: ``RuntimeReminderKit`` loads it when first needed and checks every class and method it
/// uses, so a macOS release that changes them fails with ``RemindersError/Code/reminderKitUnavailable`` rather than
/// crashing. Tests use a fake.
public protocol ReminderKitBridge: Sendable {
  /// The list's sections as ReminderKit fetches them, with what it exposes about their order.
  func sections(in list: ReminderList) throws(RemindersError) -> ReminderKitSections
  /// The list's membership data, or nil when this ReminderKit doesn't expose it.
  func memberships(in list: ReminderList) throws(RemindersError) -> ReminderKitRead<StoredMemberships>?
  /// The list's reminder identifiers (upper-case dashed UUIDs) in the order the user arranged them; the value is
  /// nil when the list isn't sorted manually. Nil when this ReminderKit doesn't say.
  func manualReminderOrder(in list: ReminderList) throws(RemindersError) -> ReminderKitRead<[String]?>?
  /// Creates a section and returns it.
  func createSection(named name: String, in list: ReminderList) throws(RemindersError) -> ReminderKitSection
  /// Deletes the section with identifier `id`.
  func deleteSection(id: String, in list: ReminderList) throws(RemindersError)
  /// Puts the reminder with identifier `reminderID` in the section `sectionID` (both upper-case dashed UUIDs),
  /// taking it out of any other section. `existing` is the list's current memberships, handed over with the new one
  /// so the save never depends on ReminderKit merging a partial set.
  func assign(
    reminderID: String, toSectionID sectionID: String, in list: ReminderList,
    keeping existing: [SectionMemberships.Entry]
  ) throws(RemindersError)
}

/// Receives one diagnostic line at a time (for `REMINDERS_DEBUG`).
public typealias ReminderKitDiagnostics = @Sendable (String) -> Void

/// A section as ReminderKit reports it.
public struct ReminderKitSection: Hashable, Sendable {
  /// Upper-case dashed UUID, as in the database and the membership data.
  public var id: String
  public var displayName: String
  /// When the section was created, if ReminderKit says.
  public var createdAt: Date?

  public init(id: String, displayName: String, createdAt: Date? = nil) {
    self.id = id
    self.displayName = displayName
    self.createdAt = createdAt
  }
}

/// A list's sections as ReminderKit fetches them, and the order information it exposes.
///
/// The fetch order isn't the order the user sees: on the Mac it came back as the reverse of the app's order.
public struct ReminderKitSections: Hashable, Sendable {
  /// In the order ReminderKit fetched them.
  public var sections: [ReminderKitSection]
  /// The fetch that returned them, for diagnostics.
  public var fetchSelector: String
  /// The list's stored section order (upper-case dashed UUIDs); empty when it has none.
  public var storedOrder: [String]
  /// The property `storedOrder` came from; nil when none had one.
  public var storedOrderSelector: String?
  /// The property each section's `createdAt` came from; nil when sections expose no creation date.
  public var creationDateSelector: String?
  /// What each order property that exists gave (`name=Class[count]`), for diagnostics.
  public var orderProbes: [String]

  public init(
    sections: [ReminderKitSection], fetchSelector: String = "fetchListSectionsInList:error:",
    storedOrder: [String] = [], storedOrderSelector: String? = nil, creationDateSelector: String? = nil,
    orderProbes: [String] = []
  ) {
    self.orderProbes = orderProbes
    self.sections = sections
    self.fetchSelector = fetchSelector
    self.storedOrder = storedOrder
    self.storedOrderSelector = storedOrderSelector
    self.creationDateSelector = creationDateSelector
  }
}

/// A value read through ReminderKit, with the selector it came from, for diagnostics.
public struct ReminderKitRead<Value: Sendable>: Sendable {
  public var value: Value
  public var selector: String

  public init(_ value: Value, via selector: String) {
    self.value = value
    self.selector = selector
  }
}

extension ReminderKitRead: Equatable where Value: Equatable {}

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
