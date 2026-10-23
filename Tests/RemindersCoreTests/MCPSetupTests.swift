import Foundation
import Synchronization
import Testing

@testable import RemindersCore

private let binary = "/opt/homebrew/opt/reminders/bin/reminders"

/// Records the commands it's asked to run and answers each with the next scripted result (exit 0 by default).
private final class FakeRunner: CommandRunner {
  let calls = Mutex<[[String]]>([])
  let results = Mutex<[CommandResult]>([])

  func run(_ executable: String, _ arguments: [String]) throws(RemindersError) -> CommandResult {
    calls.withLock { $0.append([executable] + arguments) }
    return results.withLock { $0.isEmpty ? CommandResult(status: 0, output: "") : $0.removeFirst() }
  }
}

private struct Machine {
  let home: TemporaryDirectory
  let project: TemporaryDirectory
  let runner = FakeRunner()
  let setup: MCPSetup

  init(claudeInstalled: Bool = true) throws {
    home = try TemporaryDirectory()
    project = try TemporaryDirectory()
    let bin = home.file("bin")
    setup = MCPSetup(
      environment: SetupEnvironment(
        homeDirectory: home.path, currentDirectory: project.path, binaryPath: binary,
        searchPath: "relative:\(bin):/nowhere", runner: runner,
        isExecutable: { claudeInstalled && $0 == "\(bin)/claude" },
        now: { Date(timeIntervalSince1970: 1_792_800_000) }))
  }

  var claude: String { home.file("bin/claude") }
  var calls: [[String]] { runner.calls.withLock { $0 } }
}

@Suite("MCP setup: Claude Desktop and Cursor")
struct MCPSetupFileClientTests {
  @Test("Claude Desktop: created, then unchanged, then removed, with backups of each change")
  func claudeDesktop() throws {
    let machine = try Machine()
    let path = MCPSetup.claudeDesktopConfig(home: machine.home.path)
    #expect(path == machine.home.file("Library/Application Support/Claude/claude_desktop_config.json"))
    let added = try machine.setup.configure(.claudeDesktop, at: path, SetupOptions())
    #expect(added.outcome == .added)
    #expect(added.backupPath == nil)
    #expect(added.nextSteps.first?.contains("Quit Claude Desktop") == true)
    #expect(
      added.note?.contains("prompt and the System Settings › Privacy & Security › Reminders entry name `reminders`")
        == true)
    #expect(added.note?.contains("restart Claude Desktop") == true)
    let written = try #require(try ConfigFile.read(path))
    #expect(written.contains(#""command": "\#(binary)""#))
    #expect(!written.contains("\"type\""))

    let again = try machine.setup.configure(.claudeDesktop, at: path, SetupOptions())
    #expect(again.outcome == .unchanged)
    #expect(again.backupPath == nil)

    let removed = try machine.setup.configure(.claudeDesktop, at: path, SetupOptions(remove: true))
    #expect(removed.outcome == .removed)
    let backup = try #require(removed.backupPath)
    #expect(try ConfigFile.read(backup) == written)
    #expect(try ConfigFile.read(path) == "{\n  \"mcpServers\": {}\n}\n")
    #expect(try machine.setup.configure(.claudeDesktop, at: path, SetupOptions(remove: true)).outcome == .absent)
  }

  @Test("Cursor: the global file by default, a project's with --project, with a stdio type")
  func cursor() throws {
    let machine = try Machine()
    #expect(MCPSetup.cursorConfig(home: "/Users/me", project: nil) == "/Users/me/.cursor/mcp.json")
    #expect(MCPSetup.cursorConfig(home: "/Users/me", project: "/src/app") == "/src/app/.cursor/mcp.json")
    let path = MCPSetup.cursorConfig(home: machine.home.path, project: machine.project.path)
    _ = try machine.setup.configure(.cursor, at: path, SetupOptions())
    let written = try #require(try ConfigFile.read(path))
    #expect(written.contains(#""type": "stdio""#))
  }

  @Test("--dry-run shows the new file and writes nothing")
  func dryRun() throws {
    let machine = try Machine()
    let path = machine.home.file("mcp.json")
    try ConfigFile.write(#"{"mcpServers":{"other":{"command":"x"}}}"#, to: path)
    let report = try machine.setup.configure(.cursor, at: path, SetupOptions(dryRun: true))
    #expect(report.outcome == .added)
    #expect(report.dryRun)
    #expect(report.preview?.contains("\"other\"") == true)
    #expect(report.preview?.contains(binary) == true)
    #expect(try ConfigFile.read(path) == #"{"mcpServers":{"other":{"command":"x"}}}"#)
    #expect(try machine.home.entries().filter { $0.contains(".bak-") }.isEmpty)
    #expect(report.text(using: TextRenderer()).hasPrefix("✓ Would add the reminders server to Cursor\n"))
  }

  @Test("invalid JSON and a different entry leave the file alone; --force replaces with a backup")
  func refusals() throws {
    let machine = try Machine()
    let path = machine.home.file("claude_desktop_config.json")
    try ConfigFile.write("{\"mcpServers\": {", to: path)
    #expect(throws: RemindersError.self) { try machine.setup.configure(.claudeDesktop, at: path, SetupOptions()) }
    #expect(try ConfigFile.read(path) == "{\"mcpServers\": {")

    let other = #"{"mcpServers":{"reminders":{"command":"/usr/local/bin/reminders","args":["--mcp"]}}}"#
    try ConfigFile.write(other, to: path)
    do {
      _ = try machine.setup.configure(.claudeDesktop, at: path, SetupOptions())
      Issue.record("expected a conflict")
    } catch {
      #expect(error.code == .configConflict)
    }
    let replaced = try machine.setup.configure(.claudeDesktop, at: path, SetupOptions(force: true))
    #expect(replaced.outcome == .replaced)
    #expect(try ConfigFile.read(try #require(replaced.backupPath)) == other)
  }

  @Test("without a known binary path nothing is written")
  func noBinary() throws {
    let machine = try Machine()
    var environment = machine.setup.environment
    environment.binaryPath = nil
    let path = machine.home.file("mcp.json")
    #expect(throws: RemindersError.self) {
      try MCPSetup(environment: environment).configure(.cursor, at: path, .init())
    }
    #expect(try ConfigFile.read(path) == nil)
  }
}

@Suite("MCP setup: Claude Code")
struct MCPSetupClaudeCodeTests {
  @Test("claude mcp add runs with user scope and the command after --")
  func add() async throws {
    let machine = try Machine()
    let report = try await machine.setup.configureClaudeCode(scope: .user, SetupOptions())
    #expect(report.outcome == .added)
    #expect(
      machine.calls == [
        [machine.claude, "mcp", "add", "--transport", "stdio", "--scope", "user", "reminders", "--", binary, "--mcp"]
      ])
    #expect(report.configPath == machine.home.file(".claude.json"))
    #expect(report.text(using: TextRenderer()).contains("Ran: claude mcp add --transport stdio --scope user"))
  }

  @Test("an identical registration is left alone; a different one needs --force, which removes then adds")
  func existing() async throws {
    let machine = try Machine()
    let same = #"{"type":"stdio","command":"\#(binary)","args":["--mcp"],"env":{}}"#
    try ConfigFile.write(
      #"{"numStartups":3,"mcpServers":{"reminders":\#(same)}}"#, to: machine.home.file(".claude.json"))
    #expect(try await machine.setup.configureClaudeCode(scope: .user, SetupOptions()).outcome == .unchanged)
    #expect(machine.calls.isEmpty)

    let other = #"{"type":"stdio","command":"/usr/local/bin/reminders","args":["--mcp"]}"#
    try ConfigFile.write(#"{"mcpServers":{"reminders":\#(other)}}"#, to: machine.home.file(".claude.json"))
    await #expect(throws: RemindersError.self) {
      try await machine.setup.configureClaudeCode(scope: .user, SetupOptions())
    }
    #expect(machine.calls.isEmpty)
    let replaced = try await machine.setup.configureClaudeCode(scope: .user, SetupOptions(force: true))
    #expect(replaced.outcome == .replaced)
    #expect(machine.calls.map { Array($0.dropFirst().prefix(2)) } == [["mcp", "remove"], ["mcp", "add"]])
  }

  @Test("local scope reads the project's entry in ~/.claude.json; project scope its .mcp.json")
  func scopes() async throws {
    let machine = try Machine()
    let same = #"{"command":"\#(binary)","args":["--mcp"]}"#
    try ConfigFile.write(
      #"{"projects":{"\#(machine.project.path)":{"mcpServers":{"reminders":\#(same)}}}}"#,
      to: machine.home.file(".claude.json"))
    #expect(try await machine.setup.configureClaudeCode(scope: .local, SetupOptions()).outcome == .unchanged)
    #expect(try await machine.setup.configureClaudeCode(scope: .user, SetupOptions(dryRun: true)).outcome == .added)
    let project = try await machine.setup.configureClaudeCode(scope: .project, SetupOptions())
    #expect(project.configPath == machine.project.file(".mcp.json"))
    #expect(project.nextSteps.contains { $0.contains("approve") })
    #expect(machine.calls.last?.contains("project") == true)
  }

  @Test("--remove runs claude mcp remove only when there is something to remove")
  func remove() async throws {
    let machine = try Machine()
    #expect(try await machine.setup.configureClaudeCode(scope: .user, SetupOptions(remove: true)).outcome == .absent)
    #expect(machine.calls.isEmpty)
    try ConfigFile.write(
      #"{"mcpServers":{"reminders":{"command":"\#(binary)","args":["--mcp"]}}}"#, to: machine.home.file(".claude.json"))
    #expect(try await machine.setup.configureClaudeCode(scope: .user, SetupOptions(remove: true)).outcome == .removed)
    #expect(machine.calls == [[machine.claude, "mcp", "remove", "--scope", "user", "reminders"]])
  }

  @Test("without claude on PATH the exact command is shown instead, with --dry-run too")
  func manual() async throws {
    let machine = try Machine(claudeInstalled: false)
    let add = "  claude mcp add --transport stdio --scope user reminders -- \(binary) --mcp\n"
    let report = try await machine.setup.configureClaudeCode(scope: .user, SetupOptions())
    #expect(report.outcome == .manual)
    #expect(report.headline == "`claude` isn't on PATH, so nothing was changed. Run this to set up Claude Code:")
    #expect(report.text(using: TextRenderer()).contains(add))
    #expect(report.note?.contains("the app Claude Code runs in") == true)

    let dry = try await machine.setup.configureClaudeCode(scope: .user, SetupOptions(dryRun: true))
    #expect(dry.outcome == .manual)
    #expect(dry.headline.hasSuffix("nothing would change. It would print the command to set up Claude Code:"))
    #expect(dry.text(using: TextRenderer()).contains(add))
    #expect(!dry.text(using: TextRenderer()).contains("Would run"))

    let forced = try await machine.setup.configureClaudeCode(scope: .user, SetupOptions(force: true))
    #expect(forced.commands?.map { $0[2] } == ["remove", "add"])
    #expect(machine.calls.isEmpty)

    let installed = try Machine()
    let wouldRun = try await installed.setup.configureClaudeCode(scope: .user, SetupOptions(dryRun: true))
    #expect(wouldRun.outcome == .added)
    #expect(installed.calls.isEmpty)
    #expect(wouldRun.text(using: TextRenderer()).contains("Would run: claude mcp add"))
  }

  @Test("--remove without claude says it can't check and shows claude mcp remove, even if a file lists one")
  func manualRemove() async throws {
    let machine = try Machine(claudeInstalled: false)
    for dryRun in [false, true] {
      let report = try await machine.setup.configureClaudeCode(
        scope: .project, SetupOptions(dryRun: dryRun, remove: true))
      #expect(report.outcome == .manual)
      #expect(report.headline.contains("whether Claude Code has a reminders server can't be checked"))
      #expect(report.headline.hasSuffix(dryRun ? "It would print the command to remove it:" : "Run this to remove it:"))
      #expect(report.commands == [["claude", "mcp", "remove", "--scope", "project", "reminders"]])
      #expect(report.note == nil)
      #expect(report.text(using: TextRenderer()).contains("\n  claude mcp remove --scope project reminders\n"))
    }
    #expect(machine.calls.isEmpty)
  }

  @Test("a failing claude command is reported with its output")
  func failure() async throws {
    let machine = try Machine()
    machine.runner.results.withLock {
      $0 = [CommandResult(status: 1, output: "MCP server reminders already exists in user config\n")]
    }
    do {
      _ = try await machine.setup.configureClaudeCode(scope: .user, SetupOptions())
      Issue.record("expected an error")
    } catch {
      #expect(error.code == .configConflict)
      #expect(error.message.contains("already exists in user config"))
    }
    machine.runner.results.withLock { $0 = [CommandResult(status: 2, output: "boom")] }
    do {
      _ = try await machine.setup.configureClaudeCode(scope: .user, SetupOptions())
    } catch {
      #expect(error.code == .setupFailed)
    }
  }

  @Test("arguments with spaces are shell-quoted for display")
  func quoting() {
    #expect(SetupReport.shellQuoted("/Users/me/My Tools/reminders") == "'/Users/me/My Tools/reminders'")
    #expect(SetupReport.shellQuoted("it's") == #"'it'\''s'"#)
    #expect(SetupReport.shellQuoted("--mcp") == "--mcp")
  }
}

@Suite("MCP setup: what each client is told")
struct MCPSetupMessageTests {
  @Test("the permission note names the app being set up")
  func permissionNotes() {
    #expect(MCPClient.claudeDesktop.permissionNote.contains("name `reminders`"))
    #expect(MCPClient.cursor.permissionNote.contains("name Cursor"))
    #expect(MCPClient.cursor.permissionNote.contains("restart Cursor"))
    #expect(MCPClient.claudeCode.permissionNote.contains("the app Claude Code runs in"))
    for client in [MCPClient.claudeDesktop, .cursor, .claudeCode] {
      let others = [MCPClient.claudeDesktop, .cursor].filter { $0 != client }.map(\.displayName)
      #expect(others.allSatisfy { !client.permissionNote.contains($0) })
    }
  }
}
