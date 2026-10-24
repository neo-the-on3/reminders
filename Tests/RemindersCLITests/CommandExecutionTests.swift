import ArgumentParser
import Foundation
import Testing

@testable import RemindersApple
@testable import RemindersCLI
@testable import RemindersCore

/// A Mac with every check passing except, optionally, ReminderKit.
private struct HealthySystem: SystemProbe {
  var reminderKit = true
  let operatingSystemVersion: String? = "26.1"
  let embeddedInfoPlist: [String: String]? = [
    "CFBundleIdentifier": ProductInfo.bundleIdentifier, "NSRemindersFullAccessUsageDescription": "Needed",
  ]
  let hostApplication: HostApplication? = HostApplication(name: "iTerm", bundlePath: "/Applications/iTerm.app")

  func reminderKitProblem() -> String? { reminderKit ? nil : "the class REMStore is missing" }
  func openSettings(_ pane: SettingsPane) -> Bool { true }
}

/// Runs a parsed command against an in-memory store and captures what it printed.
private struct Harness {
  let store: InMemoryReminderStore
  var sections: any SectionStore = NoSectionStore()
  let output = TextBuffer()
  let errors = TextBuffer()

  init(store: InMemoryReminderStore = InMemoryReminderStore(lists: [ReminderList(id: "L1", title: "Inbox")])) {
    self.store = store
  }

  /// The exit status: 0, or the status of the `ExitCode` the command threw.
  func run(
    _ arguments: [String], store override: (any ReminderStore)? = nil, system: any SystemProbe = MacSystemProbe(),
    setup: SetupEnvironment? = nil
  ) async throws -> Int32 {
    let parsed = try RemindersCommand.parseAsRoot(arguments)
    let command = try #require(parsed as? any ConsoleCommand)
    let json = command.globals.json
    let context = CommandContext(
      console: Console(
        format: json ? .json : .text, renderer: TextRenderer(clock: .init(now: .now, timeZone: .gmt)),
        output: output, errors: errors),
      service: RemindersService(store: override ?? store, sections: sections, clock: DayClock(timeZone: .gmt)),
      system: system, setup: setup ?? .live())
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

  @Test(
    "a negative upcoming --days is INVALID_ARGUMENT, written either way", arguments: [["--days", "-1"], ["--days=-1"]])
  func negativeDays(_ days: [String]) async throws {
    let harness = Harness()
    #expect(try await harness.run(["upcoming", "--json"] + days) == 1)
    #expect(harness.errors.text.contains(#""code" : "INVALID_ARGUMENT""#))
    #expect(harness.errors.text.contains("Days must be 0 or more (got -1)"))
  }

  @Test("upcoming --days 0 is today only")
  func upcomingToday() async throws {
    let harness = Harness()
    #expect(try await harness.run(["upcoming", "--days", "0"]) == 0)
    #expect(harness.output.text.contains("Due today"))
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

  @Test("sections and list --section read the section store")
  func sectionReads() async throws {
    var harness = Harness(
      store: InMemoryReminderStore(
        lists: [ReminderList(id: "L1", title: "Inbox")],
        reminders: [
          Reminder(id: "R1", title: "Milk", listID: "L1", listName: "Inbox"),
          Reminder(id: "R2", title: "Bread", listID: "L1", listName: "Inbox"),
        ]))
    harness.sections = InMemorySectionStore(
      sections: ["L1": [Section(id: "S1", displayName: "Dairy", listName: "Inbox", sortOrder: 0)]],
      memberships: [
        "L1": StoredMemberships(
          data: #"{"minimumSupportedVersion":20230430,"memberships":[{"memberID":"R1","groupID":"S1","modifiedOn":1}]}"#
        )
      ])
    #expect(try await harness.run(["sections", "inbox"]) == 0)
    #expect(harness.output.text.contains("Dairy"))
    #expect(try await harness.run(["list", "Inbox", "--section", "dai", "--json"]) == 0)
    #expect(harness.output.text.contains(#""title" : "Milk""#))
    #expect(!harness.output.text.contains(#""title" : "Bread""#))
    #expect(try await harness.run(["list", "Inbox", "--section", "Frozen", "--json"]) == 1)
    #expect(harness.errors.text.contains("SECTION_NOT_FOUND"))
  }

  @Test("delete-section needs --confirm outside JSON mode, like delete-list")
  func deleteSectionConfirmation() async throws {
    let harness = Harness()
    #expect(try await harness.run(["delete-section", "Inbox", "Dairy"]) == 1)
    #expect(harness.errors.text.contains("Section deletion requires --confirm flag"))
    #expect(harness.errors.text.contains(#"delete-section "Inbox" "Dairy" --confirm"#))
    #expect(!harness.errors.text.contains("not implemented"))
    // Past the guard it reaches the section store, which this harness doesn't have.
    #expect(try await harness.run(["delete-section", "Inbox", "Dairy", "--confirm", "--json"]) == 1)
    #expect(try await harness.run(["delete-section", "Inbox", "Dairy", "--json"]) == 1)
    #expect(harness.errors.text.components(separatedBy: "NOT_IMPLEMENTED").count == 3)
  }

  @Test("changing sections reports NOT_IMPLEMENTED, and so do sections without a section store")
  func sectionOptions() async throws {
    let harness = Harness()
    #expect(try await harness.run(["add", "Inbox", "Milk", "--section", "Dairy", "--json"]) == 1)
    #expect(try await harness.run(["list", "Inbox", "--section", "Dairy", "--json"]) == 1)
    #expect(try await harness.run(["sections", "Inbox", "--json"]) == 1)
    #expect(harness.errors.text.components(separatedBy: "NOT_IMPLEMENTED").count == 4)
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
    #expect(try await undecided.run(["authorize", "--json"], system: HealthySystem(reminderKit: false)) == 0)
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
