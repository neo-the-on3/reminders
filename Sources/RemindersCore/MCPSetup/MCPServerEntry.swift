/// The server entry an MCP client needs to start `reminders`: the binary's absolute path and `--mcp`.
public struct MCPServerEntry: Hashable, Sendable, Encodable {
  /// The name clients list the server under.
  public static let name = "reminders"

  public var command: String
  public var args: [String]
  /// The transport, for clients whose format names it (Cursor's `"stdio"`); nil leaves it out.
  public var type: String?

  public init(command: String, args: [String] = ["--mcp"], type: String? = nil) {
    self.command = command
    self.args = args
    self.type = type
  }

  /// The entry as a config file stores it.
  var json: PersistedJSON {
    var fields: [(String, PersistedJSON)] = []
    if let type { fields.append(("type", .string(type))) }
    fields.append(("command", .string(command)))
    fields.append(("args", .array(args.map(PersistedJSON.string))))
    return .object(fields)
  }

  /// Whether `existing` starts the same server: the same command and arguments, with nothing else that changes
  /// how it runs. A `"stdio"` type and an empty `env` are equivalent to leaving them out, since clients add those
  /// themselves.
  func isEquivalent(to existing: PersistedJSON) -> Bool {
    guard let fields = existing.objectValue else { return false }
    for (key, value) in fields {
      switch key {
      case "command": guard value.stringValue == command else { return false }
      case "args": guard value.arrayValue?.map(\.stringValue) == args.map(Optional.some) else { return false }
      case "type": guard value.stringValue == "stdio" else { return false }
      case "env": guard value.objectValue?.isEmpty == true else { return false }
      default: return false
      }
    }
    return existing["command"] != nil && (existing["args"] != nil || args.isEmpty)
  }
}
