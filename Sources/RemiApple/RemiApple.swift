// Apple-only integrations for the Swift port of remi (MIT, Matthew O'Riordan).
//
// This target hosts the three layers remi uses on macOS:
//   1. EventKit (public API): lists, reminders, CRUD, recurrence, permissions. (EventKitStore.swift)
//   2. ReminderKit (private framework, loaded at runtime): section create/delete/list and sync trigger.
//   3. The Reminders Core Data SQLite store: section membership blob + checksum + token map writes.
// Layers 2 and 3 are added in later PRs. Everything Apple-specific stays behind `#if canImport(EventKit)` so
// the package keeps building (and its pure logic keeps being tested) on Linux.

import RemiCore

/// What this build of remi can do on the current platform.
public enum ApplePlatform {
  /// True when compiled for a platform with EventKit (macOS).
  public static var hasEventKit: Bool {
    #if canImport(EventKit)
      return true
    #else
      return false
    #endif
  }

  /// Error returned by Apple-only features on platforms without EventKit, or before they are ported.
  public static func unavailable(_ feature: String) -> RemiCommandError {
    #if canImport(EventKit)
      return RemiCommandError(
        .unknown, "\(feature) is not implemented yet in the Swift port",
        suggestion: "Track progress at https://github.com/neo-the-on3/reminders")
    #else
      return RemiCommandError(
        .unknown, "\(feature) requires macOS (Apple Reminders is not available on this platform)",
        suggestion: "Run remi on a Mac with macOS 26 or later")
    #endif
  }

  /// The Reminders store for this platform: EventKit on macOS, one that always fails elsewhere.
  public static func makeReminderStore() -> any ReminderStore {
    #if canImport(EventKit)
      return EventKitStore()
    #else
      return UnavailableReminderStore()
    #endif
  }

  /// Facts about this machine for `doctor` and `authorize`.
  public static func makeSystemEnvironment() -> any SystemEnvironment {
    MacSystemEnvironment()
  }
}

#if !canImport(EventKit)
  /// Stand-in store for platforms without EventKit: every operation fails with a clear error.
  final class UnavailableReminderStore: ReminderStore {
    private var error: RemiCommandError { ApplePlatform.unavailable("Apple Reminders") }
    func requestAccess() async throws -> ReminderAccess { throw error }
    func accessStatus() -> ReminderAccess { .restricted }
    func lists() async throws -> [StoreList] { throw error }
    func reminders(inLists listIDs: [String]?, completed: Bool) async throws -> [Reminder] { throw error }
    func createReminder(_ reminder: NewReminder) async throws -> String { throw error }
    func editReminder(id: String, _ edit: ReminderEdit) async throws -> String { throw error }
    func completeReminder(id: String) async throws -> String { throw error }
    func deleteReminder(id: String) async throws -> String { throw error }
    func createList(title: String) async throws -> String { throw error }
    func deleteList(id: String) async throws { throw error }
  }
#endif
