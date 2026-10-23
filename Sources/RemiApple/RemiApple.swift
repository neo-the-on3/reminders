// Apple-only integrations for the Swift port of remi (MIT, Matthew O'Riordan).
//
// This target will host the three layers remi uses on macOS:
//   1. EventKit (public API): lists, reminders, CRUD, recurrence, permissions.
//   2. ReminderKit (private framework, loaded at runtime): section create/delete/list and sync trigger.
//   3. The Reminders Core Data SQLite store: section membership blob + checksum + token map writes.
// They are added in later PRs. Everything Apple-specific stays behind `#if canImport(EventKit)` so the
// package keeps building (and its pure logic keeps being tested) on Linux.

import RemiCore

#if canImport(EventKit)
  import EventKit
#endif

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
}
