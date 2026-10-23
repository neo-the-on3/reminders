import ArgumentParser
import Foundation
import Testing

@testable import RemindersApple
@testable import RemindersCLI
@testable import RemindersCore

/// A Mac with every check passing except, optionally, Full Disk Access.
private struct HealthySystem: SystemProbe {
  var databaseAccess = true
  let operatingSystemVersion: String? = "26.1"
  let embeddedInfoPlist: [String: String]? = [
    "CFBundleIdentifier": ProductInfo.bundleIdentifier, "NSRemindersFullAccessUsageDescription": "Needed",
  ]
  let remindersDataDirectory = "/Users/test/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores"
  let hostApplication: HostApplication? = HostApplication(name: "iTerm", bundlePath: "/Applications/iTerm.app")

  func remindersDataDirectoryExists() -> Bool { true }
  func remindersDatabaseFiles() throws(RemindersError) -> [String] {
    guard databaseAccess else { throw RemindersError(.permissionDenied, "Cannot access Reminders database") }
    return ["\(remindersDataDirectory)/Data-1.sqlite"]
  }
  func openSettings(_ pane: SettingsPane) -> Bool { true }
}

/// Runs a parsed command against an in-memory store and captures what it printed.
private struct Harness {
  let store: InMemoryReminderStore
  let output = TextBuffer()
  let errors = TextBuffer()

  init(store: InMemoryReminderStore = InMemoryReminderStore(lists: [ReminderList(id: "L1", title: "Inbox")])) {
    self.store = store
  }

  /// The exit status: 0, or the status of the `ExitCode` the command threw.
  func run(
    _ arguments: [String], store override: (any ReminderStore)? = nil, system: any SystemProbe = MacSystemProbe()
  ) async throws -> Int32 {
    let parsed = try RemindersCommand.parseAsRoot(arguments)
    let command = try #require(parsed as? any ConsoleCommand)
    let json = command.globals.json
    let context = CommandContext(
      console: Console(
        format: json ? .json : .text, renderer: TextRenderer(clock: .init(now: .now, timeZone: .gmt)),
        output: output, errors: errors),
      service: RemindersService(store: override ?? store, clock: DayClock(timeZone: .gmt)),
      system: system)
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

  @Test("doctor exits 1 when a check fails, in text and JSON mode alike")
  func doctorExitStatus() async throws {
    let harness = Harness()
    #expect(try await harness.run(["doctor"], system: HealthySystem()) == 0)
    #expect(try await harness.run(["doctor", "--json"], system: HealthySystem()) == 0)
    #expect(harness.output.text.contains(#""success" : true"#))

    let denied = Harness(store: InMemoryReminderStore(access: .denied))
    #expect(try await denied.run(["doctor"], system: HealthySystem()) == 1)
    #expect(denied.output.text.contains("Reminders access: Denied for iTerm"))
    #expect(try await denied.run(["doctor", "--json"], system: HealthySystem()) == 1)
    #expect(denied.output.text.contains(#""success" : false"#))
    #expect(denied.output.text.contains(#""code" : "CHECKS_FAILED""#))
    #expect(denied.errors.text.isEmpty)
  }

  @Test("authorize exits 1 unless Reminders access ends up granted")
  func authorizeExitStatus() async throws {
    let undecided = Harness(store: InMemoryReminderStore(access: .notDetermined))
    #expect(try await undecided.run(["authorize", "--json"], system: HealthySystem(databaseAccess: false)) == 0)
    #expect(undecided.output.text.contains(#""success" : true"#))

    for access in [ReminderAccess.denied, .restricted, .writeOnly] {
      let harness = Harness(store: InMemoryReminderStore(access: access))
      #expect(try await harness.run(["authorize"], system: HealthySystem()) == 1)
      #expect(harness.output.text.contains("System Settings > Privacy & Security > Reminders"))
      #expect(try await harness.run(["authorize", "--json"], system: HealthySystem()) == 1)
      #expect(harness.output.text.contains(#""success" : false"#))
      #expect(harness.output.text.contains(#""code" : "PERMISSION_DENIED""#))
      #expect(harness.output.text.contains(#""name" : "iTerm""#))
    }

    let refused = Harness(store: InMemoryReminderStore(access: .notDetermined, promptAnswer: .denied))
    #expect(try await refused.run(["authorize", "--json"], system: HealthySystem()) == 1)
  }

  @Test("without Apple Reminders every command reports UNSUPPORTED_PLATFORM")
  func unsupportedPlatform() async throws {
    let harness = Harness()
    #expect(try await harness.run(["lists", "--json"], store: UnsupportedPlatformStore()) == 1)
    #expect(harness.errors.text.contains(#""code" : "UNSUPPORTED_PLATFORM""#))
  }
}
