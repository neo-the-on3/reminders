import RemindersCore
import Testing

@testable import RemindersApple

/// A machine where Claude started this tool and left it holding its own permissions.
private struct ClaudeDesktopLaunch: SystemProbe {
  var operatingSystemVersion: String? { "27.0" }
  var embeddedInfoPlist: [String: String]? { nil }
  func reminderKitProblem() -> String? { nil }
  var hostApplication: HostApplication? { .thisTool(at: "/opt/homebrew/bin/reminders") }
  var launchingApplication: HostApplication? { HostApplication(name: "Claude", bundlePath: "/Applications/Claude.app") }
  func openSettings(_ pane: SettingsPane) -> Bool { false }
}

@Suite("Permission guidance for how the tool was started")
struct PermissionGuidancePlatformTests {
  @Test("as an MCP server, the launching app is the client to restart; as a command, there's none")
  func launch() {
    let server = RemindersPlatform.guidance(system: ClaudeDesktopLaunch(), asMCPServer: true)
    #expect(
      server.launch == .mcpServer(client: HostApplication(name: "Claude", bundlePath: "/Applications/Claude.app")))
    #expect(server.holder == "reminders")
    #expect(server.remedy(for: .denied)?.hasPrefix("Run `reminders authorize --for-mcp` in Terminal") == true)
    #expect(server.remedy(for: .denied)?.contains("(this tool, not Claude)") == true)
    #expect(server.remedy(for: .denied)?.contains("quit and reopen Claude") == true)
    let command = RemindersPlatform.guidance(system: ClaudeDesktopLaunch(), asMCPServer: false)
    #expect(command.launch == .command)
    #expect(command.remedy(for: .denied)?.contains("Claude") == false)
  }
}
