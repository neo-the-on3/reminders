/// Facts about the machine that `doctor` and `authorize` look at. RemindersApple provides the real one.
public protocol SystemProbe: Sendable {
  /// The macOS version, such as "26.0.1"; nil when unknown.
  var operatingSystemVersion: String? { get }
  /// The Info.plist embedded in the running executable (`__TEXT,__info_plist`), if any.
  var embeddedInfoPlist: [String: String]? { get }
  /// What's missing for sections: nil when ReminderKit, the private framework sections go through, has every class
  /// and method this tool uses; otherwise the first part that isn't there.
  func reminderKitProblem() -> String?
  /// The app macOS attributes this process's permissions to; nil when no app launched it.
  var hostApplication: HostApplication? { get }
  /// Opens a System Settings pane; false when that failed.
  func openSettings(_ pane: SettingsPane) -> Bool
}

/// The System Settings panes `authorize` sends the user to.
public enum SettingsPane: String, Sendable, CaseIterable {
  case reminders = "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"

  public var url: String { rawValue }

  /// Where to find the pane by hand.
  public var location: String {
    switch self {
    case .reminders: "System Settings > Privacy & Security > Reminders"
    }
  }
}
