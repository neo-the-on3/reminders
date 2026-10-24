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

  /// Who macOS asks about Reminders access once this client starts the server, and what to allow if it was denied.
  var permissionNote: String {
    let settings = "System Settings › Privacy & Security › Reminders"
    switch self {
    case .claudeDesktop:
      return "On first use macOS asks whether `reminders` may access Reminders: Claude Desktop leaves its servers "
        + "responsible for themselves, so the prompt and the \(settings) entry name `reminders`. If tools report "
        + "PERMISSION_DENIED, turn `reminders` on there (Full Access), then restart Claude Desktop."
    case .cursor:
      return "On first use macOS asks whether Cursor may access Reminders: Cursor is responsible for the servers it "
        + "starts, so the prompt and the \(settings) entry name Cursor, and the access is shared with everything "
        + "Cursor runs. If tools report PERMISSION_DENIED, turn Cursor on there (Full Access), then restart Cursor."
    case .claudeCode:
      return "On first use macOS asks on behalf of the app Claude Code runs in (Terminal, iTerm, or an editor's "
        + "terminal), which is responsible for it, so the prompt and the \(settings) entry name that app; "
        + "`reminders authorize` run there asks ahead of time. If tools report PERMISSION_DENIED, turn that app on "
        + "there (Full Access), then restart it."
    }
  }
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

  /// This process: its home (`$HOME`, like other command-line tools), its directory, its binary and its `PATH`,
  /// with paths resolved through symlinks so they all print in one form.
  public static func live() -> SetupEnvironment {
    let manager = FileManager.default
    let environment = ProcessInfo.processInfo.environment
    let home = environment["HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? manager.homeDirectoryForCurrentUser.path
    return SetupEnvironment(
      homeDirectory: PhysicalPath.of(home), currentDirectory: PhysicalPath.of(manager.currentDirectoryPath),
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

  /// Edits the JSON config at `path` for `client` (Claude Desktop or Cursor). The report and any error name the
  /// file by its physical path (see ``PhysicalPath``), the form the backup and the server's command take too.
  public func configure(_ client: MCPClient, at path: String, _ options: SetupOptions) throws(RemindersError)
    -> SetupReport
  {
    let given = path
    let path = PhysicalPath.of(path)
    let entry = try serverEntry(type: client == .cursor ? "stdio" : nil)
    let document = try MCPConfigDocument(try ConfigFile.read(path), path: path)
    let edit =
      options.remove
      ? try document.removing(entry, force: options.force) : try document.adding(entry, force: options.force)
    // A file left with nothing but an empty `mcpServers` is deleted (after a backup, like any change), unless it's
    // reached through a symlink, which would be left dangling.
    let symlinked = ConfigFile.isSymbolicLink(given)
    let deletes = edit.leavesNothing && !symlinked
    var backup: String?
    if !options.dryRun {
      if deletes {
        backup = try ConfigFile.delete(path, now: environment.now())
      } else if let text = edit.text {
        backup = try ConfigFile.write(text, to: path, now: environment.now())
      }
    }
    var report = SetupReport(
      client: client, outcome: edit.outcome, dryRun: options.dryRun, configPath: path, backupPath: backup,
      server: entry, preview: options.dryRun && !deletes ? edit.text : nil,
      nextSteps: client.nextSteps(after: edit.outcome))
    report.fileDeleted = deletes
    report.fileKeptForSymlink = edit.leavesNothing && symlinked
    return report
  }

  /// Registers with Claude Code through `claude mcp`, or shows the commands when `claude` isn't on `PATH`.
  public func configureClaudeCode(scope: ClaudeCodeScope, _ options: SetupOptions) async throws(RemindersError)
    -> SetupReport
  {
    let entry = try serverEntry(type: nil)
    let home = environment.homeDirectory
    let project = environment.currentDirectory
    let path = ClaudeCodeRegistration.configPath(scope: scope, home: home, project: project)
    let remove = ClaudeCodeRegistration.removeArguments(scope: scope)
    let add = ClaudeCodeRegistration.addArguments(entry, scope: scope)
    let command = { (arguments: [String]) in [ClaudeCodeRegistration.executableName] + arguments }

    // Without the CLI nothing can be run, and what Claude Code has registered can't be told reliably, so the
    // commands are shown instead: the same with --dry-run as without.
    guard
      let claude = ClaudeCodeRegistration.findExecutable(
        ClaudeCodeRegistration.executableName, searchPath: environment.searchPath,
        isExecutable: environment.isExecutable)
    else {
      let plan = options.remove ? [remove] : options.force ? [remove, add] : [add]
      var report = SetupReport(
        client: .claudeCode, outcome: .manual, dryRun: options.dryRun, configPath: path, server: entry,
        commands: plan.map(command), nextSteps: MCPClient.claudeCode.nextSteps(after: .manual))
      report.removing = options.remove
      return report
    }

    let existing = ClaudeCodeRegistration.existingEntry(
      scope: scope, home: home, project: project, read: { try ConfigFile.read($0) })
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
    let report = SetupReport(
      client: .claudeCode, outcome: outcome, dryRun: options.dryRun, configPath: path, server: entry,
      commands: plan.isEmpty ? nil : plan.map(command),
      nextSteps: MCPClient.claudeCode.nextSteps(after: outcome, scope: scope))
    guard !options.dryRun else { return report }
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
  /// Whether the config file was deleted (or with `--dry-run` would be) because nothing else was left in it.
  public var fileDeleted = false
  /// Whether the config was left as an empty shell, rather than deleted, because it's reached through a symlink
  /// that deleting it would leave dangling.
  public var fileKeptForSymlink = false
  /// Whether this was `--remove`; it tells apart the two kinds of `manual` outcome.
  var removing = false
  /// About the Reminders permission prompt, once the server is registered.
  public var note: String? {
    outcome == .added || outcome == .replaced || outcome == .unchanged || (outcome == .manual && !removing)
      ? client.permissionNote : nil
  }

  private enum CodingKeys: String, CodingKey {
    case client, outcome, dryRun, configPath, fileDeleted, fileKeptForSymlink, backupPath, server, commands, preview,
      nextSteps, note
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(client, forKey: .client)
    try container.encode(outcome, forKey: .outcome)
    try container.encode(dryRun, forKey: .dryRun)
    try container.encodeIfPresent(configPath, forKey: .configPath)
    try container.encode(fileDeleted, forKey: .fileDeleted)
    try container.encode(fileKeptForSymlink, forKey: .fileKeptForSymlink)
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
    case .removed where fileDeleted:
      return (would ? "Would remove" : "Removed") + " the reminders server from \(name) and "
        + (would ? "delete" : "deleted") + " its config, which held nothing else"
    case .removed:
      return would ? "Would remove the reminders server from \(name)" : "Removed the reminders server from \(name)"
    case .unchanged: return "\(name) already has this reminders server; nothing changed"
    case .absent: return "\(name) has no reminders server; nothing to remove"
    case .manual where removing:
      return "`claude` isn't on PATH, so whether Claude Code has a reminders server can't be checked, and nothing "
        + (dryRun ? "would change. It would print the command to remove it:" : "was changed. Run this to remove it:")
    case .manual:
      return "`claude` isn't on PATH, so nothing "
        + (dryRun
          ? "would change. It would print the command to set up Claude Code:"
          : "was changed. Run this to set up Claude Code:")
    }
  }

  public func text(using renderer: TextRenderer) -> String {
    let style = renderer.style
    var text = outcome == .manual ? headline + "\n" : renderer.confirmation(headline)
    if let configPath {
      let deleted = fileDeleted ? (dryRun ? " (would be deleted)" : " (deleted)") : ""
      text += style("  Config: \(configPath)\(deleted)\n", .dim)
      if fileKeptForSymlink {
        text += style(
          "  It held nothing else, but it's reached through a symlink, so it "
            + (dryRun ? "would be" : "was") + " left as an empty config rather than deleted (deleting it would leave "
            + "the link dangling)\n", .dim)
      }
    }
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
