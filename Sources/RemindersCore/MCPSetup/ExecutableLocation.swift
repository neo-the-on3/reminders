import Foundation

/// Where the running `reminders` binary is, as a path that keeps working in a client's config.
public enum ExecutableLocation {
  /// The running binary's absolute path with symlinks resolved, or nil when the system doesn't say.
  public static func runningBinary() -> String? {
    Bundle.main.executableURL.map { $0.resolvingSymlinksInPath().path }
  }

  /// The path to write into a config for the binary at `resolved` (symlinks already resolved).
  ///
  /// A Homebrew install resolves into `<prefix>/Cellar/reminders/<version>/bin/`, which the next upgrade deletes,
  /// so the prefix's links are preferred when they exist: `opt/reminders/bin/reminders`, which always points at the
  /// installed version, then `bin/reminders`. Anything else is used as it is.
  public static func stablePath(forResolved resolved: String, exists: (String) -> Bool) -> String {
    let parts = resolved.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count >= 6, parts.suffix(2) == ["bin", "reminders"], parts[parts.count - 5] == "Cellar",
      parts[parts.count - 4] == "reminders"
    else { return resolved }
    let prefix = parts.dropLast(5).joined(separator: "/")
    let candidates = ["\(prefix)/opt/reminders/bin/reminders", "\(prefix)/bin/reminders"]
    return candidates.first(where: exists) ?? resolved
  }
}
