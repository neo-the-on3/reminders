import ArgumentParser
import Foundation
import Testing

@testable import RemindersCLI

@Suite("Command line")
struct CommandLineTests {
  @Test("aliases resolve to their commands")
  func aliases() throws {
    #expect(try RemindersCommand.parseAsRoot(["ls"]) is Lists)
    #expect(try RemindersCommand.parseAsRoot(["done", "Inbox", "Milk"]) is Complete)
    #expect(try RemindersCommand.parseAsRoot(["rm", "Inbox", "Milk", "--confirm"]) is Delete)
  }

  @Test("global flags work before or after the command")
  func globalFlags() throws {
    let before = try #require(try RemindersCommand.parseAsRoot(["--json", "lists"]) as? Lists)
    let after = try #require(try RemindersCommand.parseAsRoot(["lists", "--json"]) as? Lists)
    #expect(before.globals.json && after.globals.json)
  }

  @Test("bad values are usage errors (exit 64)")
  func usageErrors() {
    for arguments in [
      ["completions", "powershell"], ["upcoming", "--days", "soon"], ["add", "L", "T", "--priority", "urgent"],
    ] {
      #expect(throws: (any Error).self) { try RemindersCommand.parseAsRoot(arguments) }
      do {
        _ = try RemindersCommand.parseAsRoot(arguments)
      } catch {
        #expect(RemindersCommand.exitCode(for: error) == .validationFailure, "\(arguments)")
      }
    }
  }

  @Test("demo is hidden from help and from completions alike")
  func hiddenDemo() {
    #expect(!RemindersCommand.helpMessage().contains("demo"))
    for shell in CompletionShellKind.allCases {
      #expect(!CompletionScript.generate(for: shell).contains("demo"), "\(shell)")
    }
  }
}

@Suite("Shell completions")
struct CompletionTests {
  @Test(
    "every shell offers commands, aliases, the completions command itself and flags",
    arguments: CompletionShellKind.allCases)
  func coverage(_ shell: CompletionShellKind) {
    let script = CompletionScript.generate(for: shell)
    for word in ["lists", "ls", "complete", "done", "delete", "rm", "completions"] {
      #expect(script.contains(word), "\(shell) is missing \(word)")
    }
    for flag in ["json", "due", "priority", "confirm", "include-completed"] {
      let spelling = shell == .fish ? "-l '\(flag)'" : "--\(flag)"
      #expect(script.contains(spelling), "\(shell) is missing \(spelling)")
    }
    #expect(script.hasSuffix("\n"))
  }

  @Test("aliases are listed from the command configurations")
  func aliasTable() {
    #expect(
      CompletionScript.aliases.map { "\($0.name)=\($0.command)" } == ["ls=lists", "done=complete", "rm=delete"])
  }

  @Test("zsh only calls compdef when compinit has defined it")
  func zshGuard() {
    let script = CompletionScript.generate(for: .zsh)
    #expect(script.contains("if (( $+functions[compdef] )); then compdef _reminders reminders; fi"))
    #expect(!script.contains("\n    compdef _reminders reminders\n"))
  }

  @Test(
    "scripts pass the shell's own syntax check where the shell is installed", arguments: CompletionShellKind.allCases)
  func syntax(_ shell: CompletionShellKind) throws {
    guard
      let path = ["/bin", "/usr/bin", "/opt/homebrew/bin", "/usr/local/bin"].map({ "\($0)/\(shell.rawValue)" })
        .first(where: FileManager.default.isExecutableFile(atPath:))
    else { return }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("reminders-completion.\(shell.rawValue)")
    try CompletionScript.generate(for: shell).write(to: file, atomically: true, encoding: .utf8)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["-n", file.path]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
  }
}
