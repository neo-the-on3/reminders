import Foundation
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

  /// Set to `1` to print, on standard error, where each section read came from and each ReminderKit write step.
  public static let debugVariable = "REMINDERS_DEBUG"

  /// Writes a diagnostic line to standard error, never standard output, so `--json` output stays clean.
  @Sendable static func debugToStandardError(_ line: String) {
    FileHandle.standardError.write(Data("reminders debug: \(line)\n".utf8))
  }

  /// Set to `1` to read sections from the Reminders database rather than through ReminderKit.
  public static let sectionsFromDatabaseVariable = "REMINDERS_SECTIONS_FROM_DATABASE"

  /// Sections: changed through ReminderKit, and read through it too, falling back to the Reminders database where it
  /// can't answer (or always, with ``sectionsFromDatabaseVariable`` set to `1`). Off macOS there's neither, so it
  /// reports what's missing.
  public static func makeSectionStore(
    system: any SystemProbe, permissions: PermissionGuidance,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> any SectionStore {
    #if os(macOS)
      let debug: ReminderKitDiagnostics? = environment[debugVariable] == "1" ? debugToStandardError : nil
      return AppleSectionStore(
        database: DatabaseSectionStore(system: system, permissions: permissions),
        reminderKit: RuntimeReminderKit(diagnostics: debug),
        readsThroughReminderKit: environment[sectionsFromDatabaseVariable] != "1",
        diagnostics: debug)
    #else
      return NoSectionStore()
    #endif
  }

  public static func makeSystemProbe() -> any SystemProbe {
    MacSystemProbe()
  }
}
