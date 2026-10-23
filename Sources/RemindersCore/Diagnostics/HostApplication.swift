/// The app macOS attributes this process's privacy permissions to (Reminders, Full Disk Access): the app that
/// launched it, such as Terminal, iTerm, Cursor or Claude. A command-line tool never holds them itself.
public struct HostApplication: Hashable, Sendable, Codable {
  /// Display name, such as "Terminal" or "Claude".
  public var name: String
  /// The `.app` bundle, such as `/System/Applications/Utilities/Terminal.app`.
  public var bundlePath: String

  public init(name: String, bundlePath: String) {
    self.name = name
    self.bundlePath = bundlePath
  }
}

/// One process, as far as finding the host application needs.
public struct ProcessRecord: Hashable, Sendable {
  public var pid: Int32
  public var parentPID: Int32
  /// Path of the process's executable.
  public var executablePath: String

  public init(pid: Int32, parentPID: Int32, executablePath: String) {
    self.pid = pid
    self.parentPID = parentPID
    self.executablePath = executablePath
  }
}

extension HostApplication {
  /// Walks from `pid` up through its parents and returns the first `.app` bundle one of them runs from.
  ///
  /// Helpers live inside their app (`Claude.app/Contents/Frameworks/Claude Helper.app/…`), so the outermost bundle
  /// in a path is the one macOS asks about. Shells and other bare executables are skipped. The walk stops at
  /// launchd (pid 1), an unknown process, a cycle, or after 64 steps. Nil when no ancestor is an app, such as over
  /// SSH or under launchd.
  public static func enclosing(
    pid: Int32, lookup: (Int32) -> ProcessRecord?, displayName: (String) -> String? = { _ in nil }
  ) -> HostApplication? {
    var current = pid
    var visited = Set<Int32>()
    while current > 1, visited.count < 64, visited.insert(current).inserted, let process = lookup(current) {
      if let bundle = outermostBundle(in: process.executablePath) {
        let fileName = bundle.split(separator: "/").last.map(String.init) ?? bundle
        let name = displayName(bundle) ?? String(fileName.dropLast(".app".count))
        return HostApplication(name: name, bundlePath: bundle)
      }
      current = process.parentPID
    }
    return nil
  }

  /// `/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/…` → `/Applications/Claude.app`
  static func outermostBundle(in path: String) -> String? {
    var components: [Substring] = []
    for component in path.split(separator: "/", omittingEmptySubsequences: false) {
      components.append(component)
      if component.hasSuffix(".app") && component.count > ".app".count {
        return components.joined(separator: "/")
      }
    }
    return nil
  }
}
