import Foundation
import RemindersCore

/// The platform's Reminders store and machine facts: EventKit on macOS, ``UnsupportedPlatformStore`` elsewhere.
public enum RemindersPlatform {
  /// The service on this machine's stores. Errors name the app macOS attributes permissions to and, as an MCP
  /// server (`asMCPServer`), the client to restart.
  public static func makeService(system: any SystemProbe = makeSystemProbe(), asMCPServer: Bool = false)
    -> RemindersService
  {
    let permissions = guidance(system: system, asMCPServer: asMCPServer)
    return RemindersService(
      store: makeStore(), sections: makeSectionStore(system: system, permissions: permissions),
      permissions: permissions)
  }

  /// Who holds Reminders access for this process, and how it was started.
  public static func guidance(system: any SystemProbe, asMCPServer: Bool) -> PermissionGuidance {
    PermissionGuidance(
      host: system.hostApplication, launch: asMCPServer ? .mcpServer(client: system.launchingApplication) : .command)
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

  /// Sections, read and changed through ReminderKit only (nothing reads Reminders' database, so no Full Disk Access
  /// is needed). Off macOS there's no ReminderKit, so it reports what's missing.
  public static func makeSectionStore(
    system: any SystemProbe, permissions: PermissionGuidance,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> any SectionStore {
    #if os(macOS)
      let debug: ReminderKitDiagnostics? = environment[debugVariable] == "1" ? debugToStandardError : nil
      return AppleSectionStore(reminderKit: RuntimeReminderKit(diagnostics: debug), diagnostics: debug)
    #else
      return NoSectionStore()
    #endif
  }

  public static func makeSystemProbe() -> any SystemProbe {
    MacSystemProbe()
  }
}
