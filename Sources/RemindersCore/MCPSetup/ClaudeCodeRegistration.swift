import Foundation

/// Where Claude Code keeps a server: `claude mcp add --scope`.
public enum ClaudeCodeScope: String, CaseIterable, Sendable, Encodable {
  /// Every project, for you only (`~/.claude.json`).
  case user
  /// This project only, for you only (`~/.claude.json`, under the project's path).
  case local
  /// This project, for everyone who checks it out (`.mcp.json` in the project).
  case project
}

/// Registering with Claude Code goes through its own CLI, which owns its config files; they are only read here, to
/// tell an identical registration from a different one before changing anything.
public enum ClaudeCodeRegistration {
  public static let executableName = "claude"

  /// `claude mcp add`'s arguments for a stdio server: options, the name, then `--` and the command line.
  public static func addArguments(_ entry: MCPServerEntry, scope: ClaudeCodeScope) -> [String] {
    ["mcp", "add", "--transport", "stdio", "--scope", scope.rawValue, MCPServerEntry.name, "--", entry.command]
      + entry.args
  }

  public static func removeArguments(scope: ClaudeCodeScope) -> [String] {
    ["mcp", "remove", "--scope", scope.rawValue, MCPServerEntry.name]
  }

  /// The file Claude Code keeps `scope`'s servers in.
  public static func configPath(scope: ClaudeCodeScope, home: String, project: String) -> String {
    scope == .project ? "\(project)/.mcp.json" : "\(home)/.claude.json"
  }

  /// What Claude Code has registered as `reminders` in `scope`: `.missing`, or the entry. `.unknown` when its
  /// config can't be read, in which case `claude` itself reports a clash.
  static func existingEntry(
    scope: ClaudeCodeScope, home: String, project: String, read: (String) throws -> String?
  ) -> Existing {
    let text: String?
    do {
      text = try read(configPath(scope: scope, home: home, project: project))
    } catch {
      return .unknown
    }
    guard let text else { return .missing }
    guard let root = try? PersistedJSON(parsing: text) else { return .unknown }
    let servers = scope == .local ? root["projects"]?[project]?["mcpServers"] : root["mcpServers"]
    return servers?[MCPServerEntry.name].map(Existing.entry) ?? .missing
  }

  enum Existing {
    case missing, unknown
    case entry(PersistedJSON)
  }

  /// The first executable `name` in the `PATH`-style `searchPath`.
  public static func findExecutable(_ name: String, searchPath: String?, isExecutable: (String) -> Bool) -> String? {
    for directory in (searchPath ?? "").split(separator: ":") where directory.hasPrefix("/") {
      let candidate = "\(directory)/\(name)"
      if isExecutable(candidate) { return candidate }
    }
    return nil
  }
}

/// Runs a program and collects what it printed.
public protocol CommandRunner: Sendable {
  /// Runs `executable` with `arguments` and returns its exit status and combined stdout and stderr.
  func run(_ executable: String, _ arguments: [String]) async throws(RemindersError) -> CommandResult
}

public struct CommandResult: Sendable, Hashable {
  public var status: Int32
  public var output: String

  public init(status: Int32, output: String) {
    self.status = status
    self.output = output
  }
}

/// ``CommandRunner`` with `Process`, in the current directory, with no input.
public struct ProcessRunner: CommandRunner {
  public init() {}

  public func run(_ executable: String, _ arguments: [String]) throws(RemindersError) -> CommandResult {
    let process = Process()
    process.executableURL = URL(filePath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    process.standardInput = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      throw RemindersError(.setupFailed, "Cannot run \(executable): \(error.localizedDescription)")
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return CommandResult(status: process.terminationStatus, output: String(bytes: data, encoding: .utf8) ?? "")
  }
}
