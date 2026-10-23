/// Identity of the `reminders` tool, shared by the CLI, its embedded Info.plist checks and diagnostics.
public enum ProductInfo {
  /// Executable and product name.
  public static let name = "reminders"
  /// Version reported by `reminders --version`.
  public static let version = "0.1.0-dev"
  /// Bundle identifier embedded in the executable's Info.plist (and its code signature on macOS).
  public static let bundleIdentifier = "io.github.neo-the-on3.reminders"
  /// Project home, used in suggestions for features that are not available yet.
  public static let homepage = "https://github.com/neo-the-on3/reminders"
}
