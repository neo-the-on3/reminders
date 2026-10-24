/// What to tell the user about each Reminders access state, naming the app macOS attributes the permission to.
///
/// Once access has been denied, restricted or limited to write-only, macOS won't ask again: only System Settings
/// can change it, so the guidance sends the user there rather than back to `reminders authorize`.
public struct PermissionGuidance: Hashable, Sendable {
  /// How this process was started, which decides what to do once a setting changes.
  public enum Launch: Hashable, Sendable {
    /// A command typed in a terminal (or run by a script).
    case command
    /// `reminders --mcp`, started by an MCP client: the app that launched it, when known.
    case mcpServer(client: HostApplication?)
  }

  public var host: HostApplication?
  public var launch: Launch

  public init(host: HostApplication?, launch: Launch = .command) {
    self.host = host
    self.launch = launch
  }

  /// What holds the permission, such as "Terminal", or "reminders" when the tool holds it itself.
  public var holder: String { host?.name ?? "your terminal app" }

  /// Whether the tool holds its own permissions, rather than the app that started it.
  public var holderIsThisTool: Bool { host?.isThisTool ?? false }

  /// The MCP client's name when running as its server: the app that started it, or "the MCP client".
  private var clientName: String? {
    guard case .mcpServer(let client) = launch else { return nil }
    return client?.name ?? "the MCP client"
  }

  /// The System Settings entry to change, as the guidance names it. As an MCP server it's quoted and says whose it
  /// is, so a model passing the message on can't take it for the client (or the Reminders app): `"reminders" (this
  /// tool, not Claude)`, or `"Cursor" (the MCP client, which holds Reminders access for this tool)`.
  private var entry: String {
    guard let clientName else { return holder }
    return holderIsThisTool
      ? "\"\(holder)\" (this tool, not \(clientName))"
      : "\"\(holder)\" (the MCP client, which holds Reminders access for this tool)"
  }

  /// The holder in a short status: quoted, and marked as this tool, as an MCP server.
  private var statusHolder: String {
    guard clientName != nil else { return holder }
    return holderIsThisTool ? "\"\(holder)\" (this tool)" : "\"\(holder)\""
  }

  /// The `authorize` option for setting up the entry an MCP server holds itself (see ``Diagnostics/authorize``).
  public static let forMCPOption = "--for-mcp"

  /// The command an MCP error leads with, since a model relaying the error repeats a command where it would
  /// paraphrase prose: `authorize --for-mcp` in Terminal for the tool's own entry, or plain `authorize` in the
  /// client's terminal when the client holds access (from anywhere else macOS would check another app).
  private var mcpCommand: String {
    holderIsThisTool
      ? "Run `\(ProductInfo.name) authorize \(Self.forMCPOption)` in Terminal"
      : "Run `\(ProductInfo.name) authorize` in a terminal inside \(holder)"
  }

  /// Where the entry is switched on, after ``mcpCommand``.
  private var mcpSettingsPage: String {
    holderIsThisTool ? "in the System Settings page it opens" : "if System Settings opens"
  }

  /// What to do once a setting is changed. macOS reads the permission when a process starts: an app has to be
  /// restarted, and the tool picks it up the next time it runs. As an MCP server it's already running, and the
  /// client only starts a new one when it's reopened.
  public var afterChanging: String {
    if let clientName { return "then quit and reopen \(clientName) so the change takes effect" }
    return holderIsThisTool ? "then try again" : "then restart \(holder)"
  }

  private var settings: String { SettingsPane.reminders.location }

  /// A short status for `doctor`, such as "Denied for Terminal"; nil for full access.
  public func status(of access: ReminderAccess) -> String? {
    switch access {
    case .fullAccess: nil
    case .notDetermined: "Not requested yet"
    case .denied: "Denied for \(statusHolder)"
    case .restricted: "Restricted for \(statusHolder) (device management or Screen Time)"
    case .writeOnly: "Write-only for \(statusHolder) (full access needed)"
    case .unavailable: "Apple Reminders is not available on this platform"
    }
  }

  /// What to do about `access`; nil for full access.
  public func remedy(for access: ReminderAccess) -> String? {
    if clientName != nil, access != .fullAccess, access != .unavailable, access != .notDetermined {
      return mcpRemedy(for: access)
    }
    return switch access {
    case .fullAccess, .unavailable:
      nil
    case .notDetermined:
      "Run: \(ProductInfo.name) authorize, and click Allow when macOS asks about \(holder)"
    case .denied:
      "Enable \(holder) in \(settings), \(afterChanging). macOS won't ask again, so re-running "
        + "\(ProductInfo.name) authorize won't help"
    case .restricted:
      "Enable \(holder) in \(settings) if the switch is available; otherwise device management or Screen Time "
        + "blocks it and whoever manages this Mac has to allow it"
    case .writeOnly:
      "Choose Full Access for \(holder) in \(settings), \(afterChanging)"
    }
  }

  /// As an MCP server: lead with the command, then the entry to switch on, then reopening the client.
  private func mcpRemedy(for access: ReminderAccess) -> String {
    switch access {
    case .restricted:
      "\(mcpCommand) and turn on \(entry) \(mcpSettingsPage) if the switch is available (otherwise device "
        + "management or Screen Time blocks it), \(afterChanging)"
    case .writeOnly:
      "\(mcpCommand), choose Full Access for \(entry) \(mcpSettingsPage), \(afterChanging)"
    default:
      "\(mcpCommand), turn on \(entry) \(mcpSettingsPage), \(afterChanging)"
    }
  }

  /// What to do when access was requested but macOS showed no prompt and recorded no answer, which happens when
  /// the host app isn't allowed to ask (a background helper, an MCP client).
  public var unpromptedRemedy: String {
    let infoPlist =
      "check that the binary embeds its Info.plist (\(ProductInfo.name) doctor; build with scripts/build-release.sh)"
    if clientName != nil {
      if holderIsThisTool {
        return "\(mcpCommand), turn on \(entry) \(mcpSettingsPage), \(afterChanging). If \"\(holder)\" isn't "
          + "listed there, \(infoPlist)"
      }
      // A terminal app would be asked about itself, not about the client, so it has to be the client's own terminal.
      return "\(mcpCommand) and click Allow when macOS asks about \(holder) (or turn on \(entry) \(mcpSettingsPage)), "
        + afterChanging
    }
    if holderIsThisTool {
      return "Enable \(holder) in \(settings) if it is listed there. If it isn't, \(infoPlist), \(afterChanging)"
    }
    return "Enable \(holder) in \(settings) if it is listed there. If it isn't, macOS won't let \(holder) ask; "
      + "run \(ProductInfo.name) authorize from a terminal app instead"
  }

  /// The error a command reports when it can't use Reminders, after it has asked for access.
  public func error(for access: ReminderAccess) -> RemindersError {
    switch access {
    case .unavailable:
      .unsupportedPlatform
    case .notDetermined:
      RemindersError(
        .permissionDenied, "Reminders access not granted (macOS didn't show the prompt for \(statusHolder))",
        suggestion: unpromptedRemedy)
    case .fullAccess, .denied, .restricted, .writeOnly:
      RemindersError(
        .permissionDenied, "Reminders access not granted (\(status(of: access) ?? "full access"))",
        suggestion: remedy(for: access))
    }
  }
}
