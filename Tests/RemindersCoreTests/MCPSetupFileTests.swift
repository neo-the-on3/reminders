import Foundation
import Testing

@testable import RemindersCore

/// A temporary directory, removed when the value goes away.
final class TemporaryDirectory {
  /// Physical, as the setup commands report paths (on macOS the temporary folder is behind `/var` → `/private/var`).
  let path: String

  init() throws {
    let created = FileManager.default.temporaryDirectory.appending(path: "reminders-setup-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: created, withIntermediateDirectories: true)
    path = PhysicalPath.of(created)
  }

  deinit {
    try? FileManager.default.removeItem(atPath: path)
  }

  func file(_ name: String) -> String { "\(path)/\(name)" }

  func contents(_ name: String) -> String? {
    FileManager.default.contents(atPath: file(name)).flatMap { String(bytes: $0, encoding: .utf8) }
  }

  func entries() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: path).sorted()
  }
}

@Suite("MCP setup: the binary's path")
struct ExecutableLocationTests {
  @Test("a Homebrew Cellar path becomes the prefix's opt link, else its bin link")
  func homebrew() {
    let cellar = "/opt/homebrew/Cellar/reminders/0.1.0-alpha.1/bin/reminders"
    let opt = "/opt/homebrew/opt/reminders/bin/reminders"
    let bin = "/opt/homebrew/bin/reminders"
    #expect(ExecutableLocation.stablePath(forResolved: cellar) { [opt, bin].contains($0) } == opt)
    #expect(ExecutableLocation.stablePath(forResolved: cellar) { $0 == bin } == bin)
    #expect(ExecutableLocation.stablePath(forResolved: cellar) { _ in false } == cellar)
    let intel = "/usr/local/Cellar/reminders/0.2.0/bin/reminders"
    #expect(ExecutableLocation.stablePath(forResolved: intel) { _ in true } == "/usr/local/opt/reminders/bin/reminders")
  }

  @Test("other paths are used as they are")
  func elsewhere() {
    for path in [
      "/Users/me/src/reminders/.build/release/reminders", "/usr/local/bin/reminders",
      "/opt/homebrew/Cellar/other/1.0/bin/reminders", "/opt/homebrew/Cellar/reminders/1.0/libexec/reminders",
    ] {
      #expect(ExecutableLocation.stablePath(forResolved: path) { _ in true } == path)
    }
  }

  @Test("the running binary resolves to an absolute path")
  func running() throws {
    let path = try #require(ExecutableLocation.runningBinary())
    #expect(path.hasPrefix("/"))
  }
}

@Suite("MCP setup: config files")
struct ConfigFileTests {
  @Test("a missing file and its folders are created, with no backup")
  func create() throws {
    let directory = try TemporaryDirectory()
    let path = directory.file("Library/Application Support/Claude/claude_desktop_config.json")
    #expect(try ConfigFile.read(path) == nil)
    #expect(try ConfigFile.write("{}\n", to: path) == nil)
    #expect(try ConfigFile.read(path) == "{}\n")
  }

  @Test("replacing backs the original up with a timestamp and keeps its permissions")
  func replace() throws {
    let directory = try TemporaryDirectory()
    let path = directory.file("mcp.json")
    try ConfigFile.write("old\n", to: path)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    let date = Date(timeIntervalSince1970: 1_792_800_000)
    let backup = try #require(try ConfigFile.write("new\n", to: path, now: date))
    #expect(backup.hasPrefix(path + ".bak-2026"))
    #expect(try ConfigFile.read(backup) == "old\n")
    #expect(try ConfigFile.read(path) == "new\n")
    let permissions = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
    #expect(permissions == 0o600)
    // A second change in the same second gets its own backup.
    let second = try #require(try ConfigFile.write("newer\n", to: path, now: date))
    #expect(second == backup + "-2")
    #expect(try ConfigFile.read(second) == "new\n")
    #expect(try directory.entries().count == 3)
  }

  @Test("backup names use the local time")
  func backupName() {
    let date = Date(timeIntervalSince1970: 1_792_800_000)  // 2026-10-24 00:00:00 UTC
    let utc = ConfigFile.backupPath(for: "/c.json", at: date, timeZone: .gmt) { _ in false }
    #expect(utc == "/c.json.bak-20261024-000000")
    let india = ConfigFile.backupPath(for: "/c.json", at: date, timeZone: TimeZone(identifier: "Asia/Kolkata")!) {
      _ in false
    }
    #expect(india == "/c.json.bak-20261024-053000")
  }

  @Test("a symlinked config is written through the link")
  func symlink() throws {
    let directory = try TemporaryDirectory()
    let target = directory.file("dotfiles/mcp.json")
    try ConfigFile.write("{}\n", to: target)
    let link = directory.file("mcp.json")
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
    try ConfigFile.write("{\"a\": 1}\n", to: link)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link) == target)
    #expect(directory.contents("dotfiles/mcp.json") == "{\"a\": 1}\n")
  }

  @Test("writing through a dangling symlink creates its target with the usual permissions and keeps the link")
  func danglingSymlink() throws {
    let directory = try TemporaryDirectory()
    let link = directory.file("mcp.json")
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "dotfiles/mcp.json")
    try ConfigFile.write("{}\n", to: link)
    #expect(ConfigFile.isSymbolicLink(link))
    #expect(directory.contents("dotfiles/mcp.json") == "{}\n")
    let mode = try FileManager.default.attributesOfItem(atPath: directory.file("dotfiles/mcp.json"))[.posixPermissions]
    #expect((mode as? Int) == ConfigFile.newFilePermissions())
    #expect(ConfigFile.newFilePermissions() & 0o111 == 0)
    #expect(PhysicalPath.of(link) == directory.file("dotfiles/mcp.json"))
  }

  @Test("a symlink loop resolves to a path rather than hanging")
  func symlinkLoop() throws {
    let directory = try TemporaryDirectory()
    try FileManager.default.createSymbolicLink(atPath: directory.file("a"), withDestinationPath: "b")
    try FileManager.default.createSymbolicLink(atPath: directory.file("b"), withDestinationPath: "a")
    #expect(!PhysicalPath.of(directory.file("a")).isEmpty)
  }

  @Test("a file that isn't UTF-8 is refused")
  func notText() throws {
    let directory = try TemporaryDirectory()
    let path = directory.file("mcp.json")
    FileManager.default.createFile(atPath: path, contents: Data([0xFF, 0xFE, 0x00]))
    #expect(throws: RemindersError.self) { try ConfigFile.read(path) }
  }
}

@Suite("MCP setup: one form for every path")
struct PhysicalPathTests {
  @Test("symlinks, . and .. are resolved, and components that don't exist yet are kept")
  func resolving() throws {
    let directory = try TemporaryDirectory()
    try FileManager.default.createDirectory(atPath: directory.file("real/sub"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(atPath: directory.file("link"), withDestinationPath: "real")
    #expect(PhysicalPath.of(directory.file("link/sub")) == directory.file("real/sub"))
    #expect(PhysicalPath.of(directory.file("link/./sub/../new/file.json")) == directory.file("real/new/file.json"))
    #expect(PhysicalPath.of("/") == "/")
    #expect(PhysicalPath.of("/no-such-root-folder/x") == "/no-such-root-folder/x")
  }

  @Test("a config reached through a symlink is reported, backed up and written at its physical path")
  func throughSymlink() throws {
    let directory = try TemporaryDirectory()
    try FileManager.default.createDirectory(atPath: directory.file("real"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(atPath: directory.file("link"), withDestinationPath: "real")
    try ConfigFile.write(#"{"mcpServers": {}}"#, to: directory.file("real/mcp.json"))
    let setup = MCPSetup(
      environment: SetupEnvironment(
        homeDirectory: directory.path, currentDirectory: directory.path, binaryPath: "/usr/local/bin/reminders",
        searchPath: nil, runner: ProcessRunner(), isExecutable: { _ in false }))
    let report = try setup.configure(.cursor, at: directory.file("link/mcp.json"), SetupOptions())
    #expect(report.configPath == directory.file("real/mcp.json"))
    #expect(report.backupPath?.hasPrefix(directory.file("real/mcp.json.bak-")) == true)
    let text = report.text(using: TextRenderer())
    #expect(!text.contains(directory.file("link")))
  }
}
