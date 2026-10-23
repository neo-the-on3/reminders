import Foundation

/// An MCP client `reminders` can register itself with.
public enum MCPClient: String, Sendable, Encodable {
  case claudeDesktop = "claude-desktop"
  case claudeCode = "claude-code"
  case cursor

  public var displayName: String {
    switch self {
    case .claudeDesktop: "Claude Desktop"
    case .claudeCode: "Claude Code"
    case .cursor: "Cursor"
    }
  }

  /// What to do once the configuration changed.
  func nextSteps(after outcome: SetupOutcome, scope: ClaudeCodeScope? = nil) -> [String] {
    switch outcome {
    case .added, .replaced:
      var steps: [String]
      switch self {
      case .claudeDesktop: steps = ["Quit Claude Desktop completely and open it again to load the server."]
      case .claudeCode:
        steps = [
          "Start a new Claude Code session (or run /mcp) to use it; `claude mcp get reminders` shows its status."
        ]
        if scope == .project {
          steps.append(
            "Claude Code asks to approve servers from the project's .mcp.json the first time it starts there.")
        }
      case .cursor: steps = ["Restart Cursor, or turn reminders on under Customize, to load the server."]
      }
      return steps
    case .removed: return ["Restart \(displayName) to unload the server."]
    case .manual: return ["Install Claude Code (https://code.claude.com), or run the command above where `claude` is."]
    case .unchanged, .absent: return []
    }
  }

  /// Who macOS asks about Reminders access once the client starts the server.
  static let permissionNote =
    "On first use macOS asks for Reminders access. Claude Desktop leaves that to the server, so the prompt names "
    + "`reminders`; clients that take responsibility for their servers (an app's built-in terminal, for example) "
    + "are asked in their own name. If tools report PERMISSION_DENIED, allow whichever the error names under "
    + "System Settings › Privacy & Security › Reminders, then restart the client."
}

/// `--dry-run`, `--force` and `--remove`, shared by the setup commands.
public struct SetupOptions: Sendable, Hashable {
  public var dryRun = false
  public var force = false
  public var remove = false

  public init(dryRun: Bool = false, force: Bool = false, remove: Bool = false) {
    self.dryRun = dryRun
    self.force = force
    self.remove = remove
  }
}

/// The machine the setup commands look at: whose home, which binary, and how to run other programs.
public struct SetupEnvironment: Sendable {
  public var homeDirectory: String
  public var currentDirectory: String
  /// The path to register, already made stable (see ``ExecutableLocation``); nil when unknown.
  public var binaryPath: String?
  /// `PATH`, to find `claude`.
  public var searchPath: String?
  public var runner: any CommandRunner
  public var isExecutable: @Sendable (String) -> Bool
  public var now: @Sendable () -> Date

  public init(
    homeDirectory: String, currentDirectory: String, binaryPath: String?, searchPath: String?,
    runner: any CommandRunner, isExecutable: @escaping @Sendable (String) -> Bool,
    now: @escaping @Sendable () -> Date = { .now }
  ) {
    self.homeDirectory = homeDirectory
    self.currentDirectory = currentDirectory
    self.binaryPath = binaryPath
    self.searchPath = searchPath
    self.runner = runner
    self.isExecutable = isExecutable
    self.now = now
  }

  /// This process: its home (`$HOME`, like other command-line tools), its directory, its binary and its `PATH`.
  public static func live() -> SetupEnvironment {
    let manager = FileManager.default
    let environment = ProcessInfo.processInfo.environment
    let home = environment["HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? manager.homeDirectoryForCurrentUser.path
    return SetupEnvironment(
      homeDirectory: home, currentDirectory: manager.currentDirectoryPath,
      binaryPath: ExecutableLocation.runningBinary().map {
        ExecutableLocation.stablePath(forResolved: $0, exists: manager.fileExists(atPath:))
      },
      searchPath: environment["PATH"], runner: ProcessRunner(),
      isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
  }
}

/// `setup-claude`, `setup-claude-code` and `setup-cursor`: register `reminders --mcp` with a client, or remove it.
public struct MCPSetup: Sendable {
  public var environment: SetupEnvironment

  public init(environment: SetupEnvironment) {
    self.environment = environment
  }

  /// Claude Desktop's config on macOS.
  public static func claudeDesktopConfig(home: String) -> String {
    "\(home)/Library/Application Support/Claude/claude_desktop_config.json"
  }

  /// Cursor's config: global, or the project's with `project`.
  public static func cursorConfig(home: String, project: String?) -> String {
    "\(project ?? home)/.cursor/mcp.json"
  }

  /// Edits the JSON config at `path` for `client` (Claude Desktop or Cursor).
  public func configure(_ client: MCPClient, at path: String, _ options: SetupOptions) throws(RemindersError)
    -> SetupReport
  {
    let entry = try serverEntry(type: client == .cursor ? "stdio" : nil)
    let document = try MCPConfigDocument(try ConfigFile.read(path), path: path)
    let edit =
      options.remove
      ? try document.removing(entry, force: options.force) : try document.adding(entry, force: options.force)
    var backup: String?
    if let text = edit.text, !options.dryRun { backup = try ConfigFile.write(text, to: path, now: environment.now()) }
    return SetupReport(
      client: client, outcome: edit.outcome, dryRun: options.dryRun, configPath: path, backupPath: backup,
      server: entry, preview: options.dryRun ? edit.text : nil, nextSteps: client.nextSteps(after: edit.outcome))
  }

  /// Registers with Claude Code through `claude mcp`, or shows the commands when `claude` isn't on `PATH`.
  public func configureClaudeCode(scope: ClaudeCodeScope, _ options: SetupOptions) async throws(RemindersError)
    -> SetupReport
  {
    let entry = try serverEntry(type: nil)
    let home = environment.homeDirectory
    let project = environment.currentDirectory
    let path = ClaudeCodeRegistration.configPath(scope: scope, home: home, project: project)
    let existing = ClaudeCodeRegistration.existingEntry(
      scope: scope, home: home, project: project, read: { try ConfigFile.read($0) })
    let remove = ClaudeCodeRegistration.removeArguments(scope: scope)
    let add = ClaudeCodeRegistration.addArguments(entry, scope: scope)

    let outcome: SetupOutcome
    let plan: [[String]]
    switch (options.remove, existing) {
    case (false, .entry(let current)) where entry.isEquivalent(to: current): (outcome, plan) = (.unchanged, [])
    case (false, .entry(let current)):
      guard options.force else { throw Self.claudeCodeConflict(scope, current, fix: "replace it") }
      (outcome, plan) = (.replaced, [remove, add])
    case (false, _): (outcome, plan) = (.added, [add])
    case (true, .missing): (outcome, plan) = (.absent, [])
    case (true, .entry(let current)) where !options.force && !entry.isEquivalent(to: current):
      throw Self.claudeCodeConflict(scope, current, fix: "remove it anyway")
    case (true, _): (outcome, plan) = (.removed, [remove])
    }
    let commands = plan.map { [ClaudeCodeRegistration.executableName] + $0 }
    var report = SetupReport(
      client: .claudeCode, outcome: outcome, dryRun: options.dryRun, configPath: path, server: entry,
      commands: commands.isEmpty ? nil : commands,
      nextSteps: MCPClient.claudeCode.nextSteps(after: outcome, scope: scope))
    guard !plan.isEmpty, !options.dryRun else { return report }
    guard
      let claude = ClaudeCodeRegistration.findExecutable(
        ClaudeCodeRegistration.executableName, searchPath: environment.searchPath,
        isExecutable: environment.isExecutable)
    else {
      report.outcome = .manual
      report.nextSteps = MCPClient.claudeCode.nextSteps(after: .manual)
      return report
    }
    for arguments in plan {
      let result = try await environment.runner.run(claude, arguments)
      guard result.status == 0 else {
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        throw RemindersError(
          output.contains("already exists") ? .configConflict : .setupFailed,
          "`claude \(arguments.joined(separator: " "))` failed (exit \(result.status)): \(output)",
          suggestion: output.contains("already exists")
            ? "Run again with --force to replace it" : "Check `claude mcp list`, then try again")
      }
    }
    return report
  }

  private func serverEntry(type: String?) throws(RemindersError) -> MCPServerEntry {
    guard let binary = environment.binaryPath else {
      throw RemindersError(
        .setupFailed, "Cannot tell where this reminders binary is",
        suggestion: "Run it by its full path, such as /opt/homebrew/bin/reminders")
    }
    return MCPServerEntry(command: binary, type: type)
  }

  private static func claudeCodeConflict(_ scope: ClaudeCodeScope, _ existing: PersistedJSON, fix: String)
    -> RemindersError
  {
    RemindersError(
      .configConflict,
      "Claude Code already has a different \"\(MCPServerEntry.name)\" server in \(scope.rawValue) scope: "
        + existing.serialized,
      suggestion: "Run again with --force to \(fix)")
  }
}

/// What a setup command did, or with `--dry-run` would do.
public struct SetupReport: ConsoleRepresentable {
  public var client: MCPClient
  public var outcome: SetupOutcome
  public var dryRun: Bool
  /// The file that holds the client's servers.
  public var configPath: String?
  /// Where the original file was copied before it changed.
  public var backupPath: String?
  public var server: MCPServerEntry
  /// The `claude` commands run, or to run (Claude Code).
  public var commands: [[String]]?
  /// With `--dry-run`, the file as it would be written.
  public var preview: String?
  public var nextSteps: [String]
  /// About the Reminders permission prompt, once the server is registered.
  public var note: String? {
    outcome == .added || outcome == .replaced || outcome == .unchanged || outcome == .manual
      ? MCPClient.permissionNote : nil
  }

  private enum CodingKeys: String, CodingKey {
    case client, outcome, dryRun, configPath, backupPath, server, commands, preview, nextSteps, note
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(client, forKey: .client)
    try container.encode(outcome, forKey: .outcome)
    try container.encode(dryRun, forKey: .dryRun)
    try container.encodeIfPresent(configPath, forKey: .configPath)
    try container.encodeIfPresent(backupPath, forKey: .backupPath)
    try container.encode(server, forKey: .server)
    try container.encodeIfPresent(commands, forKey: .commands)
    try container.encodeIfPresent(preview, forKey: .preview)
    try container.encode(nextSteps, forKey: .nextSteps)
    try container.encodeIfPresent(note, forKey: .note)
  }

  init(
    client: MCPClient, outcome: SetupOutcome, dryRun: Bool, configPath: String?, backupPath: String? = nil,
    server: MCPServerEntry, commands: [[String]]? = nil, preview: String? = nil, nextSteps: [String]
  ) {
    self.client = client
    self.outcome = outcome
    self.dryRun = dryRun
    self.configPath = configPath
    self.backupPath = backupPath
    self.server = server
    self.commands = commands
    self.preview = preview
    self.nextSteps = nextSteps
  }

  public var headline: String {
    let name = client.displayName
    let would = dryRun && outcome.changes
    switch outcome {
    case .added: return would ? "Would add the reminders server to \(name)" : "Added the reminders server to \(name)"
    case .replaced:
      return would
        ? "Would replace \(name)'s reminders server" : "Replaced \(name)'s reminders server"
    case .removed:
      return would ? "Would remove the reminders server from \(name)" : "Removed the reminders server from \(name)"
    case .unchanged: return "\(name) already has this reminders server; nothing changed"
    case .absent: return "\(name) has no reminders server; nothing to remove"
    case .manual: return "`claude` isn't on PATH, so nothing was changed. Run this to set up Claude Code:"
    }
  }

  public func text(using renderer: TextRenderer) -> String {
    let style = renderer.style
    var text = outcome == .manual ? headline + "\n" : renderer.confirmation(headline)
    if let configPath { text += style("  Config: \(configPath)\n", .dim) }
    if let backupPath { text += style("  Backup: \(backupPath)\n", .dim) }
    text += style("  Server: \(([server.command] + server.args).map(Self.shellQuoted).joined(separator: " "))\n", .dim)
    let label = outcome == .manual ? "  " : dryRun ? "  Would run: " : "  Ran: "
    for command in commands ?? [] { text += label + command.map(Self.shellQuoted).joined(separator: " ") + "\n" }
    if let preview, let configPath { text += "\n" + style("\(configPath) would become:", .bold) + "\n" + preview }
    for step in nextSteps { text += "\n" + style("Next:", .bold) + " " + step }
    if let note { text += "\n" + style("Note:", .bold) + " " + note }
    return nextSteps.isEmpty && note == nil ? text : text + "\n"
  }

  /// `argument` as a shell word: unchanged when it's safe, otherwise single-quoted.
  static func shellQuoted(_ argument: String) -> String {
    let safe = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./:=@%+,")
    if !argument.isEmpty, argument.allSatisfy(safe.contains) { return argument }
    return "'" + argument.replacing("'", with: #"'\''"#) + "'"
  }
}
