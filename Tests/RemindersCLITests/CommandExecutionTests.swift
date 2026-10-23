import ArgumentParser
import Foundation
import Testing

@testable import RemindersApple
@testable import RemindersCLI
@testable import RemindersCore

/// Runs a parsed command against an in-memory store and captures what it printed.
private struct Harness {
  let store: InMemoryReminderStore
  let output = TextBuffer()
  let errors = TextBuffer()

  init(store: InMemoryReminderStore = InMemoryReminderStore(lists: [ReminderList(id: "L1", title: "Inbox")])) {
    self.store = store
  }

  /// The exit status: 0, or the status of the `ExitCode` the command threw.
  func run(_ arguments: [String], store override: (any ReminderStore)? = nil) async throws -> Int32 {
    let parsed = try RemindersCommand.parseAsRoot(arguments)
    let command = try #require(parsed as? any ConsoleCommand)
    let json = command.globals.json
    let context = CommandContext(
      console: Console(
        format: json ? .json : .text, renderer: TextRenderer(clock: .init(now: .now, timeZone: .gmt)),
        output: output, errors: errors),
      service: RemindersService(store: override ?? store, clock: DayClock(timeZone: .gmt)),
      system: MacSystemProbe())
    do {
      try await command.execute(in: context)
      return 0
    } catch let exit as ExitCode {
      return exit.rawValue
    }
  }
}

@Suite("Command execution")
struct CommandExecutionTests {
  @Test("add then list, in text and JSON")
  func addAndList() async throws {
    let harness = Harness()
    #expect(try await harness.run(["add", "inbox", "Milk", "--priority", "high"]) == 0)
    #expect(harness.output.text == "✓ Added \"Milk\" to \"Inbox\"\n")
    #expect(try await harness.run(["list", "Inbox", "--json"]) == 0)
    #expect(harness.output.text.contains(#""title" : "Milk""#))
    #expect(harness.output.text.contains(#""priority" : "high""#))
  }

  @Test("delete and delete-list need --confirm outside JSON mode")
  func confirmation() async throws {
    let harness = Harness()
    #expect(try await harness.run(["add", "Inbox", "Milk"]) == 0)
    #expect(try await harness.run(["rm", "Inbox", "Milk"]) == 1)
    #expect(harness.errors.text.contains("Deletion requires --confirm flag"))
    #expect(try await harness.run(["delete-list", "Inbox"]) == 1)
    #expect(harness.errors.text.contains("List deletion requires --confirm flag"))
    #expect(await harness.store.allReminders.count == 1)

    #expect(try await harness.run(["rm", "Inbox", "Milk", "--json"]) == 0)
    #expect(try await harness.run(["delete-list", "Inbox", "--confirm"]) == 0)
    #expect(try await harness.store.lists().isEmpty)
  }

  @Test("failures are a JSON error on stderr and exit status 1")
  func jsonFailure() async throws {
    let harness = Harness()
    #expect(try await harness.run(["--json", "complete", "Garden", "Weeds"]) == 1)
    #expect(harness.output.text.isEmpty)
    #expect(harness.errors.text.contains(#""success" : false"#))
    #expect(harness.errors.text.contains(#""code" : "LIST_NOT_FOUND""#))
  }

  @Test("section options report NOT_IMPLEMENTED")
  func sectionOptions() async throws {
    let harness = Harness()
    #expect(try await harness.run(["add", "Inbox", "Milk", "--section", "Dairy", "--json"]) == 1)
    #expect(try await harness.run(["list", "Inbox", "--section", "Dairy", "--json"]) == 1)
    #expect(harness.errors.text.components(separatedBy: "NOT_IMPLEMENTED").count == 3)
    #expect(await harness.store.allReminders.isEmpty)
  }

  @Test("without Apple Reminders every command reports UNSUPPORTED_PLATFORM")
  func unsupportedPlatform() async throws {
    let harness = Harness()
    #expect(try await harness.run(["lists", "--json"], store: UnsupportedPlatformStore()) == 1)
    #expect(harness.errors.text.contains(#""code" : "UNSUPPORTED_PLATFORM""#))
  }
}
