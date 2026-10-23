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
}
