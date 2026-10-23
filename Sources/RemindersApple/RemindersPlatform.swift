import RemindersCore

/// The platform's Reminders store and machine facts: EventKit on macOS, ``UnsupportedPlatformStore`` elsewhere.
public enum RemindersPlatform {
  public static func makeStore() -> any ReminderStore {
    #if canImport(EventKit)
      EventKitReminderStore()
    #else
      UnsupportedPlatformStore()
    #endif
  }

  public static func makeSystemProbe() -> any SystemProbe {
    MacSystemProbe()
  }
}
