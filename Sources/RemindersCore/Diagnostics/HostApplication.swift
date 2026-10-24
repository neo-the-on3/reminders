/// What macOS attributes this process's privacy permissions (Reminders access) to: its responsible
/// process. That's usually the app that launched it, such as Terminal, iTerm or Cursor. An app that disclaims
/// responsibility for what it starts, as Claude Desktop does for MCP servers, leaves this tool holding the
/// permissions itself, and macOS asks about `reminders` by name.
public struct HostApplication: Hashable, Sendable, Codable {
  /// Display name, such as "Terminal", or "reminders" for this tool.
  public var name: String
  /// The `.app` bundle, such as `/System/Applications/Utilities/Terminal.app`, or this tool's executable.
  public var bundlePath: String
  /// Whether this is the tool itself rather than an app.
  public var isThisTool: Bool

  public init(name: String, bundlePath: String, isThisTool: Bool = false) {
    self.name = name
    self.bundlePath = bundlePath
    self.isThisTool = isThisTool
  }

  /// This tool, holding its own permissions.
  public static func thisTool(at executablePath: String) -> HostApplication {
    HostApplication(name: ProductInfo.name, bundlePath: executablePath, isThisTool: true)
  }
}

/// The running tool, as far as finding who holds its permissions needs.
public struct ToolProcess: Hashable, Sendable {
  public var pid: Int32
  public var executablePath: String
  /// The process macOS attributes the tool's permissions to, when macOS says.
  public var responsiblePID: Int32?
  /// Whether the tool embeds its own Reminders usage description, without which macOS can't ask about it.
  public var carriesUsageDescription: Bool

  public init(pid: Int32, executablePath: String, responsiblePID: Int32?, carriesUsageDescription: Bool) {
    self.pid = pid
    self.executablePath = executablePath
    self.responsiblePID = responsiblePID
    self.carriesUsageDescription = carriesUsageDescription
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
  /// What macOS attributes `tool`'s permissions to.
  ///
  /// - When macOS reports the responsible process, that decides: the tool's own process means the tool itself;
  ///   otherwise the app enclosing the responsible process.
  /// - Otherwise it's inferred: an app that declares no Reminders usage description can't be asked about
  ///   Reminders, so when the tool carries its own and the launching app doesn't, or no app launched it, the tool
  ///   holds the permissions. Otherwise the launching app does.
  public static func responsible(
    for tool: ToolProcess, lookup: (Int32) -> ProcessRecord?, displayName: (String) -> String? = { _ in nil },
    declaresRemindersUsage: (String) -> Bool
  ) -> HostApplication? {
    let (pid, executablePath) = (tool.pid, tool.executablePath)
    if let responsiblePID = tool.responsiblePID, responsiblePID > 1 {
      if responsiblePID == pid { return .thisTool(at: executablePath) }
      if let app = enclosing(pid: responsiblePID, lookup: lookup, displayName: displayName) { return app }
    }
    let host = enclosing(pid: pid, lookup: lookup, displayName: displayName)
    if tool.carriesUsageDescription, !(host.map { declaresRemindersUsage($0.bundlePath) } ?? false) {
      return .thisTool(at: executablePath)
    }
    return host
  }

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
