import RemindersCore

/// The platform's Reminders store and machine facts: EventKit on macOS, ``UnsupportedPlatformStore`` elsewhere.
public enum RemindersPlatform {
  /// The service on this machine's stores. Errors name the app macOS attributes permissions to.
  public static func makeService(system: any SystemProbe = makeSystemProbe()) -> RemindersService {
    let permissions = PermissionGuidance(host: system.hostApplication)
    return RemindersService(
      store: makeStore(), sections: makeSectionStore(system: system, permissions: permissions),
      permissions: permissions)
  }

  public static func makeStore() -> any ReminderStore {
    #if canImport(EventKit)
      EventKitReminderStore()
    #else
      UnsupportedPlatformStore()
    #endif
  }

  /// Sections, read from the Reminders database. Off macOS there's no database, so it reports what's missing.
  public static func makeSectionStore(system: any SystemProbe, permissions: PermissionGuidance) -> any SectionStore {
    #if os(macOS)
      DatabaseSectionStore(system: system, permissions: permissions)
    #else
      NoSectionStore()
    #endif
  }

  public static func makeSystemProbe() -> any SystemProbe {
    MacSystemProbe()
  }
}
