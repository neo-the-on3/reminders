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
