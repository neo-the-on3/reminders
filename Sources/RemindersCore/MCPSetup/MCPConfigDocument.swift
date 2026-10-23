/// What setting up a client did, or would do with `--dry-run`.
public enum SetupOutcome: String, Sendable, Encodable {
  /// There was no `reminders` server; now there is.
  case added
  /// A different `reminders` server was replaced (`--force`).
  case replaced
  /// The same server was already there; nothing changed.
  case unchanged
  /// The `reminders` server was removed (`--remove`).
  case removed
  /// There was no `reminders` server to remove.
  case absent
  /// The client's own tool isn't installed, so the command to run is shown instead.
  case manual

  /// Whether the client's configuration changes.
  public var changes: Bool { self == .added || self == .replaced || self == .removed }
}

/// A client's JSON configuration with its `mcpServers` table, edited without disturbing anything else.
///
/// Claude Desktop (`claude_desktop_config.json`), Cursor (`mcp.json`) and Claude Code's files keep MCP servers by
/// name under a top-level `mcpServers` object. Only the `reminders` entry is touched: other servers, other keys
/// and their order stay as they were, and the file is re-indented the way it was indented.
public struct MCPConfigDocument: Sendable {
  /// The result of an edit: the outcome, and the new file contents when it changes.
  public struct Edit: Sendable {
    public var outcome: SetupOutcome
    public var text: String?
  }

  private var root: PersistedJSON
  private let indent: String
  private let path: String

  /// Parses `text`, the file at `path`; a missing or empty file is an empty configuration.
  public init(_ text: String?, path: String) throws(RemindersError) {
    self.path = path
    guard let text, text.contains(where: { !$0.isWhitespace }) else {
      root = .object([])
      indent = "  "
      return
    }
    do {
      root = try PersistedJSON(parsing: text)
    } catch {
      let (line, column) = error.location(in: text)
      throw RemindersError(
        .configInvalid, "\(path) isn't valid JSON (line \(line), column \(column): \(error.reason))",
        suggestion: "Fix that line, or move the file aside, then run this again; it was left unchanged")
    }
    guard root.objectValue != nil else { throw Self.misshapen(path, "its top level isn't a JSON object") }
    if let servers = root["mcpServers"], servers.objectValue == nil {
      throw Self.misshapen(path, "\"mcpServers\" isn't a JSON object")
    }
    indent = Self.indentation(of: text)
  }

  /// The `reminders` entry, compact, if there is one.
  public var existingEntry: String? { root["mcpServers"]?[MCPServerEntry.name]?.serialized }

  /// Adds `entry` as `reminders`. A different existing entry is replaced only with `force`.
  public func adding(_ entry: MCPServerEntry, force: Bool) throws(RemindersError) -> Edit {
    var servers = root["mcpServers"] ?? .object([])
    if let existing = servers[MCPServerEntry.name] {
      if entry.isEquivalent(to: existing) { return Edit(outcome: .unchanged) }
      guard force else { throw Self.conflict(path, existing, fix: "replace it (the file is backed up first)") }
    }
    let outcome: SetupOutcome = servers[MCPServerEntry.name] == nil ? .added : .replaced
    servers[MCPServerEntry.name] = entry.json
    return Edit(outcome: outcome, text: rendering(servers))
  }

  /// Removes the `reminders` entry. One that doesn't start `entry` is removed only with `force`, in case it's
  /// someone else's server under the same name.
  public func removing(_ entry: MCPServerEntry, force: Bool) throws(RemindersError) -> Edit {
    guard var servers = root["mcpServers"], let existing = servers[MCPServerEntry.name] else {
      return Edit(outcome: .absent)
    }
    guard force || entry.isEquivalent(to: existing) else {
      throw Self.conflict(path, existing, fix: "remove it anyway (the file is backed up first)")
    }
    servers[MCPServerEntry.name] = nil
    return Edit(outcome: .removed, text: rendering(servers))
  }

  private func rendering(_ servers: PersistedJSON) -> String {
    var root = root
    root["mcpServers"] = servers
    return root.pretty(indent: indent) + "\n"
  }

  /// The indentation of the first indented line: a tab, or that many spaces; two spaces when nothing is indented.
  static func indentation(of text: String) -> String {
    for line in text.split(separator: "\n").dropFirst() {
      let leading = line.prefix { $0 == " " || $0 == "\t" }
      if leading.first == "\t" { return "\t" }
      if !leading.isEmpty { return String(leading) }
    }
    return "  "
  }

  private static func misshapen(_ path: String, _ problem: String) -> RemindersError {
    RemindersError(
      .configInvalid, "\(path) isn't an MCP configuration: \(problem)",
      suggestion: "Check the file, or move it aside, then run this again; it was left unchanged")
  }

  private static func conflict(_ path: String, _ existing: PersistedJSON, fix: String) -> RemindersError {
    RemindersError(
      .configConflict, "\(path) already has a different \"\(MCPServerEntry.name)\" server: \(existing.serialized)",
      suggestion: "Run again with --force to \(fix)")
  }
}
