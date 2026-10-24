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
/// name under a top-level `mcpServers` object. An edit is spliced into the original text: only the `reminders`
/// entry and the separator before it change, so other servers, other keys, their order and spacing, one-line
/// layouts and the final newline stay byte for byte as they were, and removing an entry that was added gives the
/// original text back. A new entry follows its neighbours: on its own line at their indentation (nested with the
/// file's indent unit), or on the same line in a one-line object. A missing or empty file is written with two-space
/// indentation.
public struct MCPConfigDocument: Sendable {
  /// The result of an edit: the outcome, and the new file contents when it changes.
  public struct Edit: Sendable {
    public var outcome: SetupOutcome
    public var text: String?
    /// Removing `reminders` left nothing else in the file (no other servers, no other keys), so it can go;
    /// `text` is then the empty shell, for when the file has to stay.
    public var leavesNothing = false
  }

  private var root: PersistedJSON
  /// The original text; empty for a missing or empty file.
  private let bytes: [UInt8]
  private let indent: String
  private let newline: String
  private let path: String

  /// Parses `text`, the file at `path`; a missing or empty file is an empty configuration.
  public init(_ text: String?, path: String) throws(RemindersError) {
    self.path = path
    guard let text, text.contains(where: { !$0.isWhitespace }) else {
      (root, bytes, indent, newline) = (.object([]), [], "  ", "\n")
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
    bytes = Array(text.utf8)
    indent = Self.indentation(of: text)
    newline = text.contains("\r\n") ? "\r\n" : "\n"
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
    return Edit(outcome: outcome, text: splicedSetting(entry.json) ?? rendering(servers))
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
    let emptied = servers.objectValue?.isEmpty == true
    guard emptied, (root.objectValue?.count ?? 0) > 1 else {
      return Edit(
        outcome: .removed, text: splicedRemoval() ?? rendering(servers), leavesNothing: emptied)
    }
    // Other keys are someone else's settings and stay; the emptied `mcpServers` goes with the entry, so a file
    // setup added it to reads as it did before. An empty table configures nothing, so dropping one that was
    // already there loses nothing either.
    var trimmed = root
    trimmed["mcpServers"] = nil
    return Edit(outcome: .removed, text: splicedServersRemoval() ?? trimmed.pretty(indent: indent) + "\n")
  }

  // MARK: Splicing

  // Each returns nil when the text can't be edited in place (an empty file, a duplicated `reminders` key), and
  // the whole file is then rendered from the parsed value instead.

  private var rootLayout: JSONObjectLayout? {
    guard let start = bytes.firstIndex(where: { !Self.isWhitespace($0) }) else { return nil }
    return try? JSONObjectLayout(of: bytes, at: start)
  }

  /// The `mcpServers` member and its object's layout (the last one wins, as when parsing).
  private func serversLayout(in root: JSONObjectLayout) -> (JSONObjectLayout.Member, JSONObjectLayout)? {
    guard let member = root.members.last(where: { $0.key == "mcpServers" }),
      let layout = try? JSONObjectLayout(of: bytes, at: member.valueStart)
    else { return nil }
    return (member, layout)
  }

  private func splicedSetting(_ value: PersistedJSON) -> String? {
    guard let root = rootLayout else { return nil }
    let multiline = bytes[root.open...root.close].contains(UInt8(ascii: "\n"))
    guard let (owner, servers) = serversLayout(in: root) else {
      if root.members.contains(where: { $0.key == "mcpServers" }) { return nil }
      return inserting(
        "mcpServers", .object([(MCPServerEntry.name, value)]), into: root, ownerIndent: lineIndent(of: root.open),
        multiline: multiline)
    }
    let matches = servers.members.filter { $0.key == MCPServerEntry.name }
    guard let current = matches.last else {
      return inserting(
        MCPServerEntry.name, value, into: servers, ownerIndent: lineIndent(of: owner.start), multiline: multiline)
    }
    guard matches.count == 1 else { return nil }
    let wasMultiline = bytes[current.valueStart..<current.end].contains(UInt8(ascii: "\n"))
    return splicing(
      current.valueStart..<current.end, with: render(value, at: lineIndent(of: current.start), multiline: wasMultiline))
  }

  private func splicedRemoval() -> String? {
    guard let root = rootLayout, let (_, servers) = serversLayout(in: root) else { return nil }
    let members = servers.members
    let matches = members.indices.filter { members[$0].key == MCPServerEntry.name }
    guard matches.count == 1, let index = matches.first else { return nil }
    if members.count == 1 { return splicing(servers.open..<servers.close + 1, with: "{}") }
    return removing(member: index, of: members)
  }

  /// The text without the root's `mcpServers` member; nil unless there's exactly one, among other members.
  private func splicedServersRemoval() -> String? {
    guard let root = rootLayout else { return nil }
    let members = root.members
    let matches = members.indices.filter { members[$0].key == "mcpServers" }
    guard matches.count == 1, let index = matches.first, members.count > 1 else { return nil }
    return removing(member: index, of: members)
  }

  /// The text without `members[index]` and one separator: the one before it, or after it when it comes first.
  private func removing(member index: Int, of members: [JSONObjectLayout.Member]) -> String? {
    if index > 0 { return splicing(members[index - 1].end..<members[index].end, with: "") }
    return splicing(members[0].start..<members[1].start, with: "")
  }

  /// `object` with `key: value` added after its last member, spaced like that member.
  private func inserting(
    _ key: String, _ value: PersistedJSON, into object: JSONObjectLayout, ownerIndent: String, multiline: Bool
  ) -> String? {
    guard let last = object.members.last else {
      let filled = PersistedJSON.object([(key, value)])
      return splicing(object.open..<object.close + 1, with: render(filled, at: ownerIndent, multiline: multiline))
    }
    var gapStart = last.start
    while gapStart > 0, Self.isWhitespace(bytes[gapStart - 1]) { gapStart -= 1 }
    let gap = text(gapStart..<last.start)
    var name = ""
    PersistedJSON.quote(key, into: &name)
    name += text(last.keyEnd..<last.valueStart)
    let insertion: String
    if let lineBreak = gap.lastIndex(where: \.isNewline) {
      let indentation = String(gap[gap.index(after: lineBreak)...])
      insertion = "," + newline + indentation + name + render(value, at: indentation, multiline: true)
    } else {
      insertion = "," + gap + name + render(value, at: "", multiline: false)
    }
    return splicing(last.end..<last.end, with: insertion)
  }

  /// `value` as it would sit on a line indented by `base`: indented with the file's unit, or compact.
  private func render(_ value: PersistedJSON, at base: String, multiline: Bool) -> String {
    multiline ? value.pretty(indent: indent).replacing("\n", with: newline + base) : value.serialized
  }

  /// The whitespace that starts the line holding `offset`.
  private func lineIndent(of offset: Int) -> String {
    var start = offset
    while start > 0, bytes[start - 1] != UInt8(ascii: "\n") { start -= 1 }
    var end = start
    while end < offset, bytes[end] == UInt8(ascii: " ") || bytes[end] == UInt8(ascii: "\t") { end += 1 }
    return text(start..<end)
  }

  private func text(_ range: Range<Int>) -> String { String(validating: bytes[range], as: UTF8.self) ?? "" }

  private func splicing(_ range: Range<Int>, with replacement: String) -> String? {
    var result = bytes
    result.replaceSubrange(range, with: Array(replacement.utf8))
    return String(validating: result, as: UTF8.self)
  }

  private static func isWhitespace(_ byte: UInt8) -> Bool {
    byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
  }

  private func rendering(_ servers: PersistedJSON) -> String {
    var root = root
    root["mcpServers"] = servers
    return root.pretty(indent: indent) + "\n"
  }

  /// The indentation of the first indented line: a tab, or that many spaces; two spaces when nothing is indented.
  static func indentation(of text: String) -> String {
    for line in text.split(whereSeparator: \.isNewline).dropFirst() {
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
