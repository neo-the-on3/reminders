import Testing

@testable import RemindersCore

/// A process tree: pid → (parent, executable).
private func tree(_ processes: [Int32: (Int32, String)]) -> (Int32) -> ProcessRecord? {
  { pid in processes[pid].map { ProcessRecord(pid: pid, parentPID: $0.0, executablePath: $0.1) } }
}

@Suite("Host application")
struct HostApplicationTests {
  @Test("a shell in Terminal is attributed to Terminal")
  func terminal() {
    let lookup = tree([
      500: (400, "/workspace/.build/release/reminders"), 400: (300, "/bin/zsh"), 300: (200, "/usr/bin/login"),
      200: (1, "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"), 1: (0, "/sbin/launchd"),
    ])
    #expect(
      HostApplication.enclosing(pid: 500, lookup: lookup)
        == HostApplication(name: "Terminal", bundlePath: "/System/Applications/Utilities/Terminal.app"))
  }

  @Test("an MCP server under an app's helper is attributed to the outer app")
  func helperOfApp() {
    let lookup = tree([
      900: (800, "/usr/local/bin/reminders"),
      800: (700, "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper"),
      700: (1, "/Applications/Claude.app/Contents/MacOS/Claude"),
    ])
    let host = HostApplication.enclosing(pid: 900, lookup: lookup)
    #expect(host?.name == "Claude")
    #expect(host?.bundlePath == "/Applications/Claude.app")
  }

  @Test("the bundle's display name wins over its file name")
  func displayName() {
    let lookup = tree([
      20: (10, "/opt/homebrew/bin/reminders"), 10: (1, "/Applications/Visual Studio Code.app/Contents/MacOS/Code"),
    ])
    let host = HostApplication.enclosing(pid: 20, lookup: lookup) { path in
      path.hasSuffix("Visual Studio Code.app") ? "Code" : nil
    }
    #expect(host?.name == "Code")
  }

  @Test("no app when the chain ends at launchd, an unknown process or a cycle")
  func noApp() {
    #expect(HostApplication.enclosing(pid: 30, lookup: tree([30: (20, "/bin/zsh"), 20: (1, "/usr/sbin/sshd")])) == nil)
    #expect(HostApplication.enclosing(pid: 30, lookup: tree([30: (99, "/bin/zsh")])) == nil)
    #expect(HostApplication.enclosing(pid: 30, lookup: tree([30: (31, "/bin/zsh"), 31: (30, "/bin/bash")])) == nil)
    #expect(HostApplication.enclosing(pid: 1, lookup: tree([1: (0, "/Applications/X.app/Contents/MacOS/X")])) == nil)
  }

  @Test("only path components ending in .app count as bundles")
  func bundlePaths() {
    #expect(HostApplication.outermostBundle(in: "/Users/me/my.app.backup/bin/tool") == nil)
    #expect(HostApplication.outermostBundle(in: "/Users/me/.app/tool") == nil)
    #expect(
      HostApplication.outermostBundle(in: "/Applications/iTerm.app/Contents/MacOS/iTerm2") == "/Applications/iTerm.app")
  }

  // MARK: Responsible process

  /// Claude Desktop starting the server through its helper; Terminal starting it through a shell.
  private static var claude: (Int32) -> ProcessRecord? {
    tree([
      900: (800, "/usr/local/bin/reminders"),
      800: (700, "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper"),
      700: (1, "/Applications/Claude.app/Contents/MacOS/Claude"),
    ])
  }
  private static var terminal: (Int32) -> ProcessRecord? {
    tree([
      500: (400, "/usr/local/bin/reminders"), 400: (200, "/bin/zsh"),
      200: (1, "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
    ])
  }

  private static func responsible(
    _ pid: Int32, in lookup: @escaping (Int32) -> ProcessRecord?, responsiblePID: Int32?,
    carriesUsageDescription: Bool = true, appsDeclaringUsage: Set<String> = []
  ) -> HostApplication? {
    HostApplication.responsible(
      for: ToolProcess(
        pid: pid, executablePath: "/usr/local/bin/reminders", responsiblePID: responsiblePID,
        carriesUsageDescription: carriesUsageDescription),
      lookup: lookup,
      declaresRemindersUsage: { appsDeclaringUsage.contains($0) })
  }

  @Test("when macOS says this process is responsible (Claude Desktop's MCP servers), the tool holds permissions")
  func toolIsResponsible() {
    let host = Self.responsible(900, in: Self.claude, responsiblePID: 900)
    #expect(host == .thisTool(at: "/usr/local/bin/reminders"))
    #expect(host?.name == "reminders")
    #expect(host?.isThisTool == true)
  }

  @Test("when macOS names another responsible process, its app holds permissions")
  func appIsResponsible() {
    let host = Self.responsible(500, in: Self.terminal, responsiblePID: 200)
    #expect(host == HostApplication(name: "Terminal", bundlePath: "/System/Applications/Utilities/Terminal.app"))
    #expect(Self.responsible(900, in: Self.claude, responsiblePID: 700)?.name == "Claude")
  }

  @Test("without macOS's answer, an app that declares no Reminders usage leaves it to the tool")
  func inferred() {
    #expect(Self.responsible(900, in: Self.claude, responsiblePID: nil)?.isThisTool == true)
    let terminalApp = "/System/Applications/Utilities/Terminal.app"
    #expect(
      Self.responsible(500, in: Self.terminal, responsiblePID: nil, appsDeclaringUsage: [terminalApp])?.name
        == "Terminal")
    // Without its own usage description the tool can't be asked about, so the app is the best answer.
    #expect(
      Self.responsible(900, in: Self.claude, responsiblePID: nil, carriesUsageDescription: false)?.name == "Claude")
    // Under launchd or SSH no app is involved.
    let ssh = tree([30: (20, "/usr/local/bin/reminders"), 20: (1, "/usr/sbin/sshd")])
    #expect(Self.responsible(30, in: ssh, responsiblePID: nil)?.isThisTool == true)
    #expect(Self.responsible(30, in: ssh, responsiblePID: nil, carriesUsageDescription: false) == nil)
  }

  @Test("guidance for the tool itself names reminders and doesn't ask to restart it")
  func toolGuidance() {
    let guidance = PermissionGuidance(host: .thisTool(at: "/usr/local/bin/reminders"))
    #expect(guidance.holder == "reminders")
    #expect(guidance.status(of: .denied) == "Denied for reminders")
    let remedy = guidance.remedy(for: .denied) ?? ""
    #expect(remedy.hasPrefix("Enable reminders in System Settings"))
    #expect(remedy.contains("then try again"))
    #expect(!remedy.contains("restart reminders"))
    #expect(!guidance.unpromptedRemedy.contains("from a terminal app"))
    let terminal = PermissionGuidance(host: HostApplication(name: "Terminal", bundlePath: "/Terminal.app"))
    #expect(terminal.remedy(for: .denied)?.contains("then restart Terminal") == true)
  }
}
