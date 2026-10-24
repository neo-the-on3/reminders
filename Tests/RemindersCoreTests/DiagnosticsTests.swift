import Foundation
import Synchronization
import Testing

@testable import RemindersCore

/// A machine whose facts the test chooses.
private final class FakeSystem: SystemProbe {
  let operatingSystemVersion: String?
  let embeddedInfoPlist: [String: String]?
  private let reminderKit: Bool
  private let opened = Mutex<[SettingsPane]>([])

  let hostApplication: HostApplication?

  init(
    version: String? = "26.1", plist: Bool = true, reminderKit: Bool = true,
    host: HostApplication? = HostApplication(name: "Terminal", bundlePath: FakeSystem.terminalPath)
  ) {
    hostApplication = host
    operatingSystemVersion = version
    embeddedInfoPlist =
      plist
      ? ["CFBundleIdentifier": ProductInfo.bundleIdentifier, "NSRemindersFullAccessUsageDescription": "Needed"] : nil
    self.reminderKit = reminderKit
  }

  static let terminalPath = "/System/Applications/Utilities/Terminal.app"

  var openedPanes: [SettingsPane] { opened.withLock { $0 } }

  func reminderKitProblem() -> String? { reminderKit ? nil : "REMListSectionsDataView has no method x" }

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
        "macOS version", "Info.plist", "Permissions app", "Sections (ReminderKit)", "Reminders access",
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

  @Test("old macOS fails; a missing Info.plist and ReminderKit warn")
  func problems() async {
    let report = await diagnostics(system: FakeSystem(version: "15.4", plist: false, reminderKit: false)).checkHealth()
    let statuses = Dictionary(uniqueKeysWithValues: report.checks.map { ($0.name, $0.status) })
    #expect(statuses["macOS version"] == .fail)
    #expect(statuses["Info.plist"] == .warn)
    #expect(statuses["Sections (ReminderKit)"] == .warn)
    #expect(report.failureCount == 1)
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
        ✓ Sections (ReminderKit): Available
        ✗ Reminders access: Denied for Terminal
          Enable Terminal in System Settings > Privacy & Security > Reminders, then restart Terminal. macOS won't ask again, so re-running reminders authorize won't help

        1 issue(s) found.

        """)
  }

  @Test("authorize asks for Reminders access, the only permission needed, and opens nothing once granted")
  func authorize() async {
    let system = FakeSystem()
    let (console, output, _) = makeConsole()
    let result = await diagnostics(access: .notDetermined, system: system).authorize(narratingTo: console)
    #expect(result.remindersAccess == .fullAccess)
    #expect(system.openedPanes.isEmpty)
    #expect(output.text.contains("✓ Reminders access granted (1 list found)"))
    #expect(!output.text.contains("Full Disk Access"))
    #expect(!output.text.contains("atabase"))
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
    #expect(output.text.contains(#"Opening System Settings — turn on "Terminal" under Reminders."#))
  }

  @Test("authorize run as the tool itself after a denial or restriction opens Settings and names \"reminders\"")
  func authorizeOwnEntryBlocked() async {
    for access in [ReminderAccess.denied, .restricted] {
      let system = FakeSystem(host: .thisTool(at: "/opt/homebrew/bin/reminders"))
      let (console, output, _) = makeConsole()
      let result = await diagnostics(access: access, system: system).authorize(narratingTo: console)
      #expect(result.remindersAccess == access)
      #expect(system.openedPanes == [.reminders])
      #expect(output.text.contains(#"Opening System Settings — turn on "reminders" under Reminders."#))
      #expect(!output.text.contains("If a system dialog appears"))
    }
  }

  @Test("authorize --for-mcp from a terminal still prompts first, then opens Settings at the tool's own entry")
  func authorizeForMCPServer() async {
    let system = FakeSystem()
    let (console, output, _) = makeConsole()
    let result = await diagnostics(access: .notDetermined, system: system)
      .authorize(narratingTo: console, forMCPServer: true)
    #expect(result.remindersAccess == .fullAccess)
    #expect(output.text.contains("If a system dialog appears, click Allow."))
    #expect(output.text.contains("✓ Reminders access granted"))
    #expect(system.openedPanes == [.reminders])
    #expect(
      output.text.contains(
        #"Opening System Settings — turn on "reminders" under Reminders, then quit and reopen the MCP client."#))
  }

  @Test("authorize --for-mcp after the terminal's own denial opens Settings once for both entries")
  func authorizeForMCPServerAfterDenial() async {
    let system = FakeSystem()
    let (console, output, _) = makeConsole()
    _ = await diagnostics(access: .denied, system: system).authorize(narratingTo: console, forMCPServer: true)
    #expect(system.openedPanes == [.reminders])
    #expect(output.text.contains(#"turn on "Terminal" under Reminders"#))
    #expect(output.text.contains(#"In the same page, turn on "reminders" under Reminders"#))
  }

  @Test("authorize --for-mcp run as the tool itself needs nothing extra")
  func authorizeForMCPServerAsTheTool() async {
    let system = FakeSystem(host: .thisTool(at: "/opt/homebrew/bin/reminders"))
    let (console, output, _) = makeConsole()
    _ = await diagnostics(access: .fullAccess, system: system).authorize(narratingTo: console, forMCPServer: true)
    #expect(system.openedPanes.isEmpty)
    #expect(!output.text.contains("For MCP clients"))
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

  @Test("authorize only fails without full Reminders access; ReminderKit doesn't count")
  func authorizeFailure() async {
    let (console, _, _) = makeConsole(json: true)
    let granted = diagnostics(system: FakeSystem(reminderKit: false))
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
