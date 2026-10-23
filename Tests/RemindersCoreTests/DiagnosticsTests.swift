import Foundation
import Synchronization
import Testing

@testable import RemindersCore

/// A machine whose facts the test chooses.
private final class FakeSystem: SystemProbe {
  let operatingSystemVersion: String?
  let embeddedInfoPlist: [String: String]?
  let remindersDataDirectory = "/Users/test/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores"
  private let databases: [String]?
  private let opened = Mutex<[SettingsPane]>([])

  let hostApplication: HostApplication?

  init(
    version: String? = "26.1", plist: Bool = true, databases: [String]? = ["Data-1.sqlite"],
    host: HostApplication? = HostApplication(name: "Terminal", bundlePath: FakeSystem.terminalPath)
  ) {
    hostApplication = host
    operatingSystemVersion = version
    embeddedInfoPlist =
      plist
      ? ["CFBundleIdentifier": ProductInfo.bundleIdentifier, "NSRemindersFullAccessUsageDescription": "Needed"] : nil
    self.databases = databases
  }

  static let terminalPath = "/System/Applications/Utilities/Terminal.app"

  var openedPanes: [SettingsPane] { opened.withLock { $0 } }

  func remindersDataDirectoryExists() -> Bool { databases != nil }

  func remindersDatabaseFiles() throws(RemindersError) -> [String] {
    guard let databases else { throw RemindersError(.permissionDenied, "Cannot access Reminders database") }
    return databases.map { "\(remindersDataDirectory)/\($0)" }
  }

  func openSettings(_ pane: SettingsPane) -> Bool {
    opened.withLock { $0.append(pane) }
    return true
  }
}

private func diagnostics(
  access: ReminderAccess = .fullAccess, promptAnswer: ReminderAccess = .fullAccess, system: FakeSystem = FakeSystem()
) -> Diagnostics {
  let store = InMemoryReminderStore(
    lists: [ReminderList(id: "L", title: "Inbox")], access: access, promptAnswer: promptAnswer)
  return Diagnostics(service: RemindersService(store: store, clock: utcClock), system: system)
}

@Suite("Diagnostics")
struct DiagnosticsTests {
  @Test("a healthy Mac passes every check")
  func healthy() async {
    let report = await diagnostics().checkHealth()
    #expect(report.passed)
    #expect(
      report.checks.map(\.name) == [
        "macOS version", "Info.plist", "Permissions app", "Reminders database", "Reminders access",
        "Reminders data dir",
      ])
    #expect(report.checks.allSatisfy { $0.status == .ok })
    #expect(report.checks[2].message == "Terminal")
    #expect(report.checks[4].message == "Granted (1 list)")
  }

  @Test("doctor never prompts: undecided access fails with a hint")
  func undecided() async throws {
    let report = await diagnostics(access: .notDetermined).checkHealth()
    let access = try #require(report.checks.first { $0.name == "Reminders access" })
    #expect(access.status == .fail)
    #expect(access.message == "Not requested yet")
    #expect(access.detail == "Run: reminders authorize, and click Allow when macOS asks about Terminal")
  }

  @Test("each access state gets its own status and remedy")
  func accessStates() async throws {
    let expected: [(ReminderAccess, String, String)] = [
      (.denied, "Denied for Terminal", "Enable Terminal in System Settings > Privacy & Security > Reminders"),
      (.restricted, "Restricted for Terminal (device management or Screen Time)", "Enable Terminal in System Settings"),
      (.writeOnly, "Write-only for Terminal (full access needed)", "Choose Full Access for Terminal"),
    ]
    for (state, message, remedy) in expected {
      let report = await diagnostics(access: state).checkHealth()
      let access = try #require(report.checks.first { $0.name == "Reminders access" })
      #expect(access.status == .fail)
      #expect(access.message == message)
      #expect(access.detail?.hasPrefix(remedy) == true, "\(access.detail ?? "")")
      #expect(access.detail?.contains("Run: reminders authorize") == false)
    }
  }

  @Test("an unknown host app warns and falls back to 'your terminal app'")
  func unknownHost() async throws {
    let report = await diagnostics(access: .denied, system: FakeSystem(host: nil)).checkHealth()
    let host = try #require(report.checks.first { $0.name == "Permissions app" })
    #expect(host.status == .warn)
    let access = try #require(report.checks.first { $0.name == "Reminders access" })
    #expect(access.message == "Denied for your terminal app")
  }

  @Test("old macOS fails; a missing Info.plist and database access warn")
  func problems() async {
    let report = await diagnostics(system: FakeSystem(version: "15.4", plist: false, databases: nil)).checkHealth(
      includeDatabaseStats: true, includeSync: true)
    let statuses = Dictionary(uniqueKeysWithValues: report.checks.map { ($0.name, $0.status) })
    #expect(statuses["macOS version"] == .fail)
    #expect(statuses["Info.plist"] == .warn)
    #expect(statuses["Reminders database"] == .warn)
    #expect(statuses["Database stats"] == .warn)
    #expect(statuses["Sync"] == .warn)
    #expect(statuses["Reminders data dir"] == .fail)
    #expect(report.failureCount == 2)
  }

  @Test("the summary counts warnings instead of claiming every check passed")
  func summary() {
    let ok = HealthCheck("A", .ok, "Fine")
    let warn = HealthCheck("B", .warn, "Hmm")
    let fail = HealthCheck("C", .fail, "Broken")
    let cases: [([HealthCheck], String)] = [
      ([ok], "All checks passed."),
      ([ok, warn], "All required checks passed (1 warning)."),
      ([warn, warn], "All required checks passed (2 warnings)."),
      ([fail, warn], "1 issue(s) found (1 warning)."),
      ([fail], "1 issue(s) found."),
    ]
    for (checks, expected) in cases {
      let (console, output, _) = makeConsole()
      console.show(HealthReport(checks))
      #expect(output.text.hasSuffix("\n\(expected)\n"), "\(output.text)")
    }
  }

  @Test("the text report matches the reference layout")
  func text() async {
    let (console, output, _) = makeConsole()
    console.show(await diagnostics(access: .denied).checkHealth())
    #expect(
      output.text == """

        reminders doctor
        ────────────────────────────────────────
        ✓ macOS version: macOS 26.1
        ✓ Info.plist: Embedded (io.github.neo-the-on3.reminders)
        ✓ Permissions app: Terminal
          /System/Applications/Utilities/Terminal.app
        ✓ Reminders database: Found
          /Users/test/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores/Data-1.sqlite
        ✗ Reminders access: Denied for Terminal
          Enable Terminal in System Settings > Privacy & Security > Reminders, then restart Terminal. macOS won't ask again, so re-running reminders authorize won't help
        ✓ Reminders data dir: Exists

        1 issue(s) found.

        """)
  }

  @Test("authorize asks for access and opens Settings only for what's missing")
  func authorize() async {
    let system = FakeSystem(databases: nil)
    let (console, output, _) = makeConsole()
    let result = await diagnostics(access: .notDetermined, system: system).authorize(narratingTo: console)
    #expect(result.remindersAccess == .fullAccess)
    #expect(!result.databaseAccess)
    #expect(system.openedPanes == [.fullDiskAccess])
    #expect(output.text.contains("✓ Reminders access granted (1 list found)"))
    #expect(output.text.contains("✗ Database access not yet granted."))
    #expect(output.text.contains("Full Disk Access for Terminal"))
  }

  @Test("authorize after a denial points to System Settings instead of prompting again")
  func authorizeAfterDenial() async {
    let system = FakeSystem()
    let (console, output, _) = makeConsole()
    let result = await diagnostics(access: .denied, system: system).authorize(narratingTo: console)
    #expect(result.remindersAccess == .denied)
    #expect(system.openedPanes == [.reminders])
    #expect(!output.text.contains("If a system dialog appears"))
    #expect(output.text.contains("✗ Reminders access: Denied for Terminal."))
    #expect(output.text.contains("macOS won't show the prompt again"))
    #expect(output.text.contains("Enable Terminal in System Settings > Privacy & Security > Reminders"))
  }

  @Test("authorize explains a prompt macOS never showed")
  func authorizeUnprompted() async {
    let claude = HostApplication(name: "Claude", bundlePath: "/Applications/Claude.app")
    let (console, output, _) = makeConsole()
    let result = await diagnostics(
      access: .notDetermined, promptAnswer: .notDetermined, system: FakeSystem(host: claude)
    ).authorize(narratingTo: console)
    #expect(result.remindersAccess == .notDetermined)
    #expect(output.text.contains("✗ macOS didn't show the Reminders prompt for Claude."))
    #expect(output.text.contains("Enable Claude in System Settings > Privacy & Security > Reminders if it is listed"))
  }

  @Test("authorize reports a prompt the user refuses")
  func authorizeRefused() async {
    let (console, output, _) = makeConsole()
    let result = await diagnostics(access: .notDetermined, promptAnswer: .denied).authorize(narratingTo: console)
    #expect(result.remindersAccess == .denied)
    #expect(output.text.contains("If a system dialog appears, click Allow."))
    #expect(output.text.contains("✗ Reminders access: Denied for Terminal."))
    #expect(!output.text.contains("macOS won't show the prompt again"))
  }

  @Test("authorize with --json prints only the outcome, failing without access")
  func authorizeJSON() async throws {
    let (console, output, _) = makeConsole(json: true)
    let diagnostics = diagnostics(access: .denied)
    let report = await diagnostics.authorize(narratingTo: console)
    let failure = try #require(diagnostics.failure(of: report))
    console.show(report, failure: failure)
    #expect(failure.code == .permissionDenied)
    #expect(
      output.text == """
        {
          "data" : {
            "databaseAccess" : true,
            "host" : {
              "bundlePath" : "/System/Applications/Utilities/Terminal.app",
              "isThisTool" : false,
              "name" : "Terminal"
            },
            "remindersAccess" : "denied"
          },
          "error" : {
            "code" : "PERMISSION_DENIED",
            "message" : "Reminders access not granted (Denied for Terminal)",
            "suggestion" : "\(try #require(failure.suggestion))"
          },
          "success" : false
        }

        """)
  }

  @Test("authorize only fails without full Reminders access; database access doesn't count")
  func authorizeFailure() async {
    let (console, _, _) = makeConsole(json: true)
    let granted = diagnostics(system: FakeSystem(databases: nil))
    #expect(granted.failure(of: await granted.authorize(narratingTo: console)) == nil)
    for access in [ReminderAccess.notDetermined, .denied, .restricted, .writeOnly] {
      let denied = diagnostics(access: access, promptAnswer: .denied)
      #expect(denied.failure(of: await denied.authorize(narratingTo: console))?.code == .permissionDenied)
    }
    let unavailable = diagnostics(access: .unavailable)
    #expect(unavailable.failure(of: await unavailable.authorize(narratingTo: console))?.code == .unsupportedPlatform)
  }

  @Test("a failing check makes the JSON report a CHECKS_FAILED failure that still carries the checks")
  func doctorJSONFailure() async throws {
    let report = await diagnostics(access: .denied).checkHealth()
    let failure = try #require(report.failure)
    #expect(failure.code == .checksFailed)
    #expect(failure.message == "1 check(s) failed: Reminders access")
    #expect(await diagnostics().checkHealth().failure == nil)

    let (console, output, errors) = makeConsole(json: true)
    console.show(report, failure: failure)
    #expect(errors.text.isEmpty)
    let json = try #require(
      try JSONSerialization.jsonObject(with: Data(output.text.utf8)) as? [String: Any])
    #expect(json["success"] as? Bool == false)
    #expect((json["error"] as? [String: Any])?["code"] as? String == "CHECKS_FAILED")
    #expect((json["data"] as? [Any])?.count == report.checks.count)
  }
}
