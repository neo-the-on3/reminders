// Port of remi tests/integration/crud.test.ts and tests/helpers/test-list.ts (MIT, Matthew O'Riordan).
//
// Creates, edits and deletes real reminders in a throwaway list named `_remi_test_<hex>`, through the built
// `remi` binary with `--json`. Opt-in, because it needs a Mac with Reminders access granted:
//
//   REMI_INTEGRATION=1 swift test --filter RemiIntegrationTests
//
// Set REMI_BINARY to test a specific binary (e.g. a signed release build); otherwise the debug build that
// `swift test` produces is used.

import Foundation
import RemiCore
import Testing

private let enabled = ProcessInfo.processInfo.environment["REMI_INTEGRATION"] == "1"

@Suite(
  "CRUD integration (Apple Reminders)", .serialized,
  .enabled(if: enabled, "Set REMI_INTEGRATION=1 to run against Apple Reminders (creates and deletes a test list)"))
struct CrudIntegrationTests {
  @Test("add, list, complete, update, search and delete in a throwaway list")
  func crudLifecycle() throws {
    try cleanupStaleTestLists()
    let listName = "_remi_test_" + String(UInt32.random(in: 0...0xFF_FFFF), radix: 16).leftPadded(to: 6)
    _ = try remi("create-list", listName)
    defer { _ = try? remi("delete-list", listName, "--confirm") }

    // lists shows the test list
    let lists = try remi("lists").arrayValue ?? []
    #expect(lists.contains { $0["title"]?.stringValue == listName })

    // add creates a reminder
    let added = try remi("add", listName, "Integration test item")
    #expect(added["id"]?.stringValue?.isEmpty == false)

    // list shows the created reminder
    #expect(try item(listName, "Integration test item") != nil)

    // add with due date and priority
    _ = try remi("add", listName, "Urgent task", "--due", "2026-12-25", "--priority", "high")
    let urgent = try #require(try item(listName, "Urgent task"))
    #expect(urgent["dueDate"]?.stringValue == "2026-12-25")
    #expect(urgent["priority"]?.stringValue == "high")

    // add with natural language date
    _ = try remi("add", listName, "NLP date task", "--due", "tomorrow")
    #expect(try item(listName, "NLP date task")?["dueDate"]?.stringValue != nil)

    // add with recurrence
    _ = try remi("add", listName, "Recurring task", "--due", "2026-12-25", "--repeat", "weekly")
    let recurring = try #require(try item(listName, "Recurring task"))
    #expect(recurring["isRecurring"]?.boolValue == true)
    #expect(recurring["recurrence"]?.stringValue == "weekly")

    // complete marks a reminder done
    _ = try remi("complete", listName, "Integration test item")
    #expect(try item(listName, "Integration test item") == nil)

    // update changes reminder properties
    _ = try remi("update", listName, "Urgent task", "--title", "Updated task", "--priority", "low")
    #expect(try item(listName, "Updated task")?["priority"]?.stringValue == "low")

    // search finds reminders across lists
    let found = try remi("search", "Updated task").arrayValue ?? []
    #expect(found.contains { $0["title"]?.stringValue == "Updated task" && $0["listName"]?.stringValue == listName })

    // delete removes a reminder
    _ = try remi("delete", listName, "NLP date task", "--confirm")
    #expect(try item(listName, "NLP date task") == nil)

    // create-list is idempotent
    let again = try remi("create-list", listName)
    #expect(again["id"]?.stringValue?.isEmpty == false)
    let matching = (try remi("lists").arrayValue ?? []).filter { $0["title"]?.stringValue == listName }
    #expect(matching.count == 1)
  }
}

// MARK: - Helpers (tests/helpers/test-list.ts)

struct RemiFailure: Error, CustomStringConvertible {
  let arguments: [String]
  let status: Int32
  let stdout: String
  let stderr: String
  var description: String { "remi \(arguments.joined(separator: " ")) exited \(status)\n\(stdout)\(stderr)" }
}

/// Run `remi <arguments> --json` and return the `data` of its success response.
@discardableResult
func remi(_ arguments: String...) throws -> JSONValue {
  let process = Process()
  process.executableURL = remiBinary()
  process.arguments = arguments + ["--json"]
  let out = Pipe()
  let err = Pipe()
  process.standardOutput = out
  process.standardError = err
  try process.run()
  let stdoutData = out.fileHandleForReading.readDataToEndOfFile()
  let stderrData = err.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  let stdout = String(bytes: stdoutData, encoding: .utf8) ?? ""
  let stderr = String(bytes: stderrData, encoding: .utf8) ?? ""
  guard process.terminationStatus == 0, let response = try? JSONValue.parse(stdout),
    response["success"]?.boolValue == true
  else {
    throw RemiFailure(arguments: arguments, status: process.terminationStatus, stdout: stdout, stderr: stderr)
  }
  return response["data"] ?? .null
}

/// The incomplete reminder titled `title` in `list`, if any.
func item(_ list: String, _ title: String) throws -> JSONValue? {
  try remi("list", list).arrayValue?.first { $0["title"]?.stringValue == title }
}

/// Delete lists left behind by earlier interrupted runs.
func cleanupStaleTestLists() throws {
  for list in try remi("lists").arrayValue ?? [] {
    if let title = list["title"]?.stringValue, title.hasPrefix("_remi_test_") {
      _ = try? remi("delete-list", title, "--confirm")
    }
  }
}

/// REMI_BINARY, or the `remi` next to this test bundle (the build `swift test` just made).
func remiBinary() -> URL {
  if let path = ProcessInfo.processInfo.environment["REMI_BINARY"], !path.isEmpty {
    return URL(fileURLWithPath: path)
  }
  let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
  for configuration in ["debug", "release"] {
    let candidate = packageRoot.appendingPathComponent(".build/\(configuration)/remi")
    if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
  }
  return packageRoot.appendingPathComponent(".build/debug/remi")
}

extension String {
  fileprivate func leftPadded(to length: Int) -> String {
    String(repeating: "0", count: max(0, length - count)) + self
  }
}
