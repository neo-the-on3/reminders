import ArgumentParser
import Foundation
import Testing

@testable import RemindersCLI
@testable import RemindersCore

/// Runs nothing; the setup commands under test never get that far without `claude` on `PATH`.
private struct NoRunner: CommandRunner {
  func run(_ executable: String, _ arguments: [String]) throws(RemindersError) -> CommandResult {
    Issue.record("unexpected command \(executable)")
    return CommandResult(status: 1, output: "")
  }
}

/// A home directory in a temporary folder, and the setup environment that points at it.
private struct FakeHome {
  let path: String
  let environment: SetupEnvironment

  init() throws {
    let created = FileManager.default.temporaryDirectory.appending(path: "reminders-cli-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: created, withIntermediateDirectories: true)
    path = PhysicalPath.of(created)
    environment = SetupEnvironment(
      homeDirectory: path, currentDirectory: path, binaryPath: "/opt/homebrew/opt/reminders/bin/reminders",
      searchPath: nil, runner: NoRunner(), isExecutable: { _ in false })
  }

  func read(_ relative: String) -> String? {
    FileManager.default.contents(atPath: "\(path)/\(relative)").flatMap { String(bytes: $0, encoding: .utf8) }
  }

  func remove() { try? FileManager.default.removeItem(atPath: path) }
}

/// Runs `arguments` with output in buffers; returns the exit status and what went to stdout and stderr.
private func run(_ arguments: [String], in home: FakeHome) async throws -> (Int32, String, String) {
  let command = try #require(try RemindersCommand.parseAsRoot(arguments) as? any ConsoleCommand)
  let output = TextBuffer()
  let errors = TextBuffer()
  let context = CommandContext(
    console: Console(format: command.globals.json ? .json : .text, output: output, errors: errors),
    service: RemindersService(store: InMemoryReminderStore()), system: DatabaseFreeProbe(), setup: home.environment)
  do {
    try await command.execute(in: context)
    return (0, output.text, errors.text)
  } catch let exit as ExitCode {
    return (exit.rawValue, output.text, errors.text)
  }
}

/// No machine facts are needed by the setup commands.
private struct DatabaseFreeProbe: SystemProbe {
  var operatingSystemVersion: String? { "26.0" }
  var embeddedInfoPlist: [String: String]? { nil }
  var remindersDataDirectory: String { "/nowhere" }
  func remindersDataDirectoryExists() -> Bool { false }
  func remindersDatabaseFiles() throws(RemindersError) -> [String] { [] }
  var hostApplication: HostApplication? { nil }
  func openSettings(_ pane: SettingsPane) -> Bool { false }
}

@Suite("Setup commands")
struct SetupCommandTests {
  @Test("setup-claude writes Claude Desktop's config under the home directory, then reports it unchanged")
  func claude() async throws {
    let home = try FakeHome()
    defer { home.remove() }
    let (status, output, _) = try await run(["setup-claude"], in: home)
    #expect(status == 0)
    #expect(output.hasPrefix("✓ Added the reminders server to Claude Desktop\n"))
    #expect(output.contains("Next: Quit Claude Desktop"))
    let config = try #require(home.read("Library/Application Support/Claude/claude_desktop_config.json"))
    #expect(config.contains(#""args": ["--mcp"]"#))
    let (_, again, _) = try await run(["setup-claude", "--json"], in: home)
    #expect(again.contains(#""outcome" : "unchanged""#))
  }

  @Test("setup-cursor --project writes the project's file; --dry-run and --remove behave")
  func cursor() async throws {
    let home = try FakeHome()
    defer { home.remove() }
    #expect(try await run(["setup-cursor", "--dry-run"], in: home).0 == 0)
    #expect(home.read(".cursor/mcp.json") == nil)
    try FileManager.default.createDirectory(atPath: "\(home.path)/app", withIntermediateDirectories: true)
    #expect(try await run(["setup-cursor", "--project", "app"], in: home).0 == 0)
    #expect(home.read("app/.cursor/mcp.json")?.contains(#""type": "stdio""#) == true)
    let (status, output, _) = try await run(["setup-cursor", "--project", "app", "--remove", "--json"], in: home)
    #expect(status == 0)
    #expect(output.contains(#""outcome" : "removed""#))
    #expect(output.contains(#""backupPath""#))
    #expect(try await run(["setup-cursor", "--project", "missing"], in: home).2.contains("isn't a directory"))
    #expect(throws: (any Error).self) {
      try RemindersCommand.parseAsRoot(["setup-cursor", "--project", "app", "--config", "x.json"])
    }
    #expect(try await run(["setup-cursor", "--config", "x.json"], in: home).0 == 0)
    #expect(home.read("x.json")?.contains("reminders") == true)
  }

  @Test("a conflicting entry fails with CONFIG_CONFLICT until --force")
  func conflict() async throws {
    let home = try FakeHome()
    defer { home.remove() }
    let path = "\(home.path)/custom.json"
    try ConfigFile.write(#"{"mcpServers":{"reminders":{"command":"/old/reminders"}}}"#, to: path)
    let (status, _, errors) = try await run(["setup-claude", "--config", path, "--json"], in: home)
    #expect(status == 1)
    #expect(errors.contains(#""code" : "CONFIG_CONFLICT""#))
    #expect(try await run(["setup-claude", "--config", path, "--force"], in: home).0 == 0)
  }

  @Test("setup-claude-code without claude prints the command; --scope is validated")
  func claudeCode() async throws {
    let home = try FakeHome()
    defer { home.remove() }
    let (status, output, _) = try await run(["setup-claude-code", "--scope", "project"], in: home)
    #expect(status == 0)
    #expect(output.contains("claude mcp add --transport stdio --scope project reminders -- "))
    #expect(throws: (any Error).self) { try RemindersCommand.parseAsRoot(["setup-claude-code", "--scope", "team"]) }
  }

  @Test("setup-claude-code --dry-run and --remove without claude match the real run: commands shown, nothing run")
  func claudeCodeWithoutCLI() async throws {
    let home = try FakeHome()
    defer { home.remove() }
    let (_, dry, _) = try await run(["setup-claude-code", "--dry-run", "--json"], in: home)
    #expect(dry.contains(#""outcome" : "manual""#))
    let (_, remove, _) = try await run(["setup-claude-code", "--remove"], in: home)
    #expect(remove.contains("can't be checked"))
    #expect(remove.contains("  claude mcp remove --scope user reminders\n"))
  }

  @Test("--verbose says what it changes")
  func verboseHelp() {
    let help = RemindersCommand.helpMessage(for: SetupCursor.self)
    #expect(help.contains("Preview each reminder's notes when listing reminders"))
    #expect(!help.contains("full dates"))
  }

  @Test("reports name the config file and its backup by one physical path")
  func physicalPaths() async throws {
    let home = try FakeHome()
    defer { home.remove() }
    try FileManager.default.createDirectory(atPath: "\(home.path)/real", withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(atPath: "\(home.path)/link", withDestinationPath: "real")
    try ConfigFile.write("{}", to: "\(home.path)/real/mcp.json")
    let (_, output, _) = try await run(["setup-cursor", "--config", "\(home.path)/link/mcp.json"], in: home)
    #expect(output.contains("Config: \(home.path)/real/mcp.json\n"))
    #expect(output.contains("Backup: \(home.path)/real/mcp.json.bak-"))
    #expect(!output.contains("/link/"))
    #expect(output.contains("name Cursor"))
  }
}
