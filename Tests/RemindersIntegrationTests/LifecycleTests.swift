// End-to-end tests against Apple Reminders. They create, change and delete real reminders, but only inside a
// throwaway list named `_reminders_test_<hex>`, which is removed afterwards (and by the next run if a run is
// interrupted). Opt-in, because they need a Mac where the terminal has Reminders access:
//
//   REMINDERS_INTEGRATION=1 swift test --filter RemindersIntegrationTests
//
// They drive the `reminders` binary with `--json`: the debug build `swift test` makes, or REMINDERS_BINARY (for
// example a signed release build from scripts/build-release.sh).

import Foundation
import Testing

private let isEnabled = ProcessInfo.processInfo.environment["REMINDERS_INTEGRATION"] == "1"

@Suite(
  "Apple Reminders lifecycle", .serialized,
  .enabled(if: isEnabled, "Set REMINDERS_INTEGRATION=1 to run against Apple Reminders (uses a throwaway list)"))
struct LifecycleTests {
  @Test("Lists, adds, completes, updates, searches and deletes in a throwaway list")
  func lifecycle() throws {
    let cli = try CLI()
    try cli.removeLeftoverTestLists()
    let list = CLI.testListPrefix + String(UInt32.random(in: 0...0xFF_FFFF), radix: 16)
    let created: Created = try cli.run("create-list", list)
    #expect(!(created.id ?? "").isEmpty)
    defer { try? cli.runIgnoringOutput("delete-list", list, "--confirm") }

    let lists: [ListItem] = try cli.run("lists")
    #expect(lists.contains { $0.title == list && $0.reminderCount == 0 })

    let added: Created = try cli.run("add", list, "Plain item")
    #expect(!(added.id ?? "").isEmpty)
    #expect(try cli.reminder("Plain item", in: list) != nil)

    try cli.runIgnoringOutput("add", list, "Urgent item", "--due", "2026-12-25", "--priority", "high")
    let urgent = try #require(try cli.reminder("Urgent item", in: list))
    #expect(urgent.dueDate == "2026-12-25")
    #expect(urgent.priority == "high")

    try cli.runIgnoringOutput("add", list, "Tomorrow item", "--due", "tomorrow", "--notes", "needle in notes")
    #expect(try cli.reminder("Tomorrow item", in: list)?.dueDate != nil)

    try cli.runIgnoringOutput("add", list, "Weekly item", "--due", "2026-12-25", "--repeat", "every 2 weeks")
    let weekly = try #require(try cli.reminder("Weekly item", in: list))
    #expect(weekly.isRecurring)
    #expect(weekly.recurrence == "every 2 weeks")

    try cli.runIgnoringOutput("complete", list, "Plain item")
    #expect(try cli.reminder("Plain item", in: list) == nil)
    let everything: [ReminderItem] = try cli.run("list", list, "--include-completed")
    #expect(everything.contains { $0.title == "Plain item" && $0.isCompleted })

    try cli.runIgnoringOutput(
      "update", list, "Urgent item", "--title", "Renamed item", "--priority", "low", "--clear-due")
    let renamed = try #require(try cli.reminder("Renamed item", in: list))
    #expect(renamed.priority == "low")
    #expect(renamed.dueDate == nil)

    let found: [ReminderItem] = try cli.run("search", "needle in")
    #expect(found.contains { $0.title == "Tomorrow item" && $0.listName == list })

    let upcoming: [ReminderItem] = try cli.run("upcoming", "--days", "2")
    #expect(upcoming.contains { $0.title == "Tomorrow item" })

    try cli.runIgnoringOutput("delete", list, "Tomorrow item", "--confirm")
    #expect(try cli.reminder("Tomorrow item", in: list) == nil)

    let again: Created = try cli.run("create-list", list)
    #expect(again.id == created.id)
    let matching: [ListItem] = try cli.run("lists")
    #expect(matching.count { $0.title == list } == 1)
  }

  @Test("Deleting without --confirm is refused outside JSON mode")
  func deleteNeedsConfirmation() throws {
    let cli = try CLI()
    let result = try cli.launch(["delete-list", "\(CLI.testListPrefix)never", "--confirm-not-a-flag"])
    #expect(result.status == 64)
    let refused = try cli.launch(["delete-list", "\(CLI.testListPrefix)never"])
    #expect(refused.status == 1)
    #expect(refused.standardError.contains("--confirm"))
  }
}

// MARK: - Driving the binary

/// The `reminders` binary under test: REMINDERS_BINARY, or the build `swift test` made.
func remindersBinary() throws -> URL {
  if let path = ProcessInfo.processInfo.environment["REMINDERS_BINARY"], !path.isEmpty {
    return URL(filePath: path)
  }
  let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
  return try #require(
    ["debug", "release"].map { root.appending(path: ".build/\($0)/reminders") }
      .first { FileManager.default.isExecutableFile(atPath: $0.path) },
    "Build reminders first or set REMINDERS_BINARY")
}

private struct Envelope<Payload: Decodable>: Decodable {
  var success: Bool
  var data: Payload
}

private struct Created: Decodable {
  var id: String?
}

private struct ListItem: Decodable {
  var title: String
  var reminderCount: Int
}

private struct ReminderItem: Decodable {
  var title: String
  var listName: String
  var isCompleted: Bool
  var priority: String
  var dueDate: String?
  var isRecurring: Bool
  var recurrence: String?
}

private struct CommandFailure: Error, CustomStringConvertible {
  var arguments: [String]
  var status: Int32
  var output: String

  var description: String { "reminders \(arguments.joined(separator: " ")) exited \(status):\n\(output)" }
}

private struct CLI {
  static let testListPrefix = "_reminders_test_"
  let binary: URL

  init() throws {
    binary = try remindersBinary()
  }

  /// `reminders <arguments> --json`, decoding the `data` of its success envelope.
  func run<Payload: Decodable>(_ arguments: String...) throws -> Payload {
    try decode(arguments)
  }

  func runIgnoringOutput(_ arguments: String...) throws {
    let _: Created = try decode(arguments)
  }

  /// The incomplete reminder titled `title` in `list`, if any.
  func reminder(_ title: String, in list: String) throws -> ReminderItem? {
    let reminders: [ReminderItem] = try run("list", list)
    return reminders.first { $0.title == title }
  }

  /// Removes test lists that interrupted runs left behind.
  func removeLeftoverTestLists() throws {
    let lists: [ListItem] = try run("lists")
    for list in lists where list.title.hasPrefix(Self.testListPrefix) {
      try? runIgnoringOutput("delete-list", list.title, "--confirm")
    }
  }

  private func decode<Payload: Decodable>(_ arguments: [String]) throws -> Payload {
    let result = try launch(arguments + ["--json"])
    guard result.status == 0,
      let envelope = try? JSONDecoder().decode(Envelope<Payload>.self, from: Data(result.standardOutput.utf8)),
      envelope.success
    else {
      throw CommandFailure(
        arguments: arguments, status: result.status, output: result.standardOutput + result.standardError)
    }
    return envelope.data
  }

  func launch(_ arguments: [String]) throws -> (status: Int32, standardOutput: String, standardError: String) {
    let process = Process()
    process.executableURL = binary
    process.arguments = arguments
    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (
      process.terminationStatus, String(bytes: outputData, encoding: .utf8) ?? "",
      String(bytes: errorData, encoding: .utf8) ?? ""
    )
  }
}
