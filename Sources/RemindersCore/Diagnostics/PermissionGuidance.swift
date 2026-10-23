/// What to tell the user about each Reminders access state, naming the app macOS attributes the permission to.
///
/// Once access has been denied, restricted or limited to write-only, macOS won't ask again: only System Settings
/// can change it, so the guidance sends the user there rather than back to `reminders authorize`.
public struct PermissionGuidance: Hashable, Sendable {
  public var host: HostApplication?

  public init(host: HostApplication?) {
    self.host = host
  }

  /// What holds the permission, such as "Terminal", or "reminders" when the tool holds it itself.
  public var holder: String { host?.name ?? "your terminal app" }

  /// Whether the tool holds its own permissions, rather than the app that started it.
  public var holderIsThisTool: Bool { host?.isThisTool ?? false }

  /// What to do once a setting is changed: an app has to be restarted to pick it up; the tool just runs again
  /// (an MCP client may keep the old server running until it is restarted).
  public var afterChanging: String {
    holderIsThisTool
      ? "then try again (restart the MCP client if \(holder) runs as its server)" : "then restart \(holder)"
  }

  private var settings: String { SettingsPane.reminders.location }

  /// A short status for `doctor`, such as "Denied for Terminal"; nil for full access.
  public func status(of access: ReminderAccess) -> String? {
    switch access {
    case .fullAccess: nil
    case .notDetermined: "Not requested yet"
    case .denied: "Denied for \(holder)"
    case .restricted: "Restricted for \(holder) (device management or Screen Time)"
    case .writeOnly: "Write-only for \(holder) (full access needed)"
    case .unavailable: "Apple Reminders is not available on this platform"
    }
  }

  /// What to do about `access`; nil for full access.
  public func remedy(for access: ReminderAccess) -> String? {
    switch access {
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

  /// What to do when access was requested but macOS showed no prompt and recorded no answer, which happens when
  /// the host app isn't allowed to ask (a background helper, an MCP client).
  public var unpromptedRemedy: String {
    if holderIsThisTool {
      return "Enable \(holder) in \(settings) if it is listed there. If it isn't, check that the binary embeds its "
        + "Info.plist (\(ProductInfo.name) doctor; build with scripts/build-release.sh), then try again"
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
        .permissionDenied, "Reminders access not granted (macOS didn't show the prompt for \(holder))",
        suggestion: unpromptedRemedy)
    case .fullAccess, .denied, .restricted, .writeOnly:
      RemindersError(
        .permissionDenied, "Reminders access not granted (\(status(of: access) ?? "full access"))",
        suggestion: remedy(for: access))
    }
  }
}
