// Ported from remi tests/unit/output.test.ts, plus byte-for-byte parity with remi's output.ts.

import Foundation
import Testing

@testable import RemiCore

struct OutputCase: Sendable, CustomTestStringConvertible {
  let name: String
  let verbose: Bool
  let color: Bool
  let json: Bool
  let stdout: String
  let stderr: String

  init(_ name: String, verbose: Bool, color: Bool, json: Bool, stdout: String, stderr: String) {
    self.name = name
    self.verbose = verbose
    self.color = color
    self.json = json
    self.stdout = stdout
    self.stderr = stderr
  }

  var testDescription: String { "\(name) verbose=\(verbose) color=\(color) json=\(json)" }
}

private func makeOutput(json: Bool = false, verbose: Bool = false, color: Bool = false) -> (
  Output, StringSink, StringSink
) {
  let out = StringSink()
  let err = StringSink()
  let frozen = ISO8601DateFormatter().date(from: "2026-10-23T10:00:00Z")!
  let output = Output(
    jsonMode: json, verboseMode: verbose, style: Styler(level: color ? .trueColor : .none), stdout: out, stderr: err,
    now: { frozen }, timeZone: TimeZone(identifier: "UTC")!)
  return (output, out, err)
}

// Same sample data as scripts/output-fixtures.mts
private let sampleReminders: [Reminder] = [
  Reminder(
    id: "A1", title: "Buy milk", listID: "L1", listName: "Groceries", priority: .high, dueDate: "2026-10-23",
    notes: "Organic only, the big bottle from the shop round the corner please", section: "Dairy", flagged: true),
  Reminder(
    id: "A2", title: "Pay rent", listID: "L2", listName: "Home", priority: .medium, dueDate: "2026-10-20",
    isRecurring: true, recurrence: "monthly"),
  Reminder(
    id: "A3", title: "Call mum", isCompleted: true, listID: "L2", listName: "Home", priority: .none,
    dueDate: "2026-10-22", completionDate: "2026-10-22"),
  Reminder(
    id: "A4", title: "Dentist", listID: "L2", listName: "Home", priority: .low, dueDate: "2026-10-24", isRecurring: true
  ),
  Reminder(id: "A5", title: "Renew passport", listID: "L2", listName: "Home", dueDate: "2026-11-15"),
  Reminder(id: "A6", title: "File taxes", listID: "L3", listName: "Admin", dueDate: "2027-04-01", section: "Money"),
  Reminder(id: "A7", title: "Read book", listID: "L3", listName: "Admin", notes: "Short note"),
  Reminder(id: "A8", title: "Soon", listID: "L3", listName: "Admin", dueDate: "2026-10-28", section: "Dairy"),
]

private let sampleLists = [
  ReminderList(id: "L1", title: "Groceries", reminderCount: 12, overdueCount: 0),
  ReminderList(id: "L2", title: "Home 🏠", reminderCount: 3, overdueCount: 2),
  ReminderList(id: "L3", title: "Ad", reminderCount: 0, overdueCount: 0),
]

private let sampleSections = [
  Section(id: "S1", displayName: "Dairy", listName: "Groceries", sortOrder: 0),
  Section(id: "S2", displayName: "Produce", listName: "Groceries", sortOrder: 1),
]

private func render(_ name: String, _ output: Output) {
  switch name {
  case "lists": output.lists(sampleLists)
  case "listsEmpty": output.lists([])
  case "remindersPlain": output.reminders(sampleReminders)
  case "remindersEmpty": output.reminders([], listName: "Groceries")
  case "remindersList":
    output.reminders(sampleReminders, listName: "Groceries", options: .init(context: .list, groupBySections: true))
  case "remindersToday":
    output.reminders(sampleReminders, options: .init(context: .today, showList: true, sortByDate: true))
  case "remindersOverdue": output.reminders(sampleReminders, options: .init(context: .overdue, showList: true))
  case "remindersSorted": output.reminders(sampleReminders, listName: "All", options: .init(sortByDate: true))
  case "sections": output.sections(sampleSections, listName: "Groceries", counts: ["Dairy": 3])
  case "sectionsEmpty": output.sections([], listName: "Groceries")
  case "message": output.message("Created reminder")
  case "error":
    output.error(
      RemiError(code: "LIST_NOT_FOUND", message: "No list matching \"x\"", suggestion: "Available lists:\n  - A\n  - B")
    )
  default: Issue.record("unknown case \(name)")
  }
}

@Suite("output")
struct OutputTests {
  // MARK: Ported from output.test.ts — JSON mode

  @Test("JSON mode wraps data in success result")
  func jsonSuccess() throws {
    let (output, out, _) = makeOutput(json: true)
    output.success(JSONValue.object([("items", [1, 2, 3].jsonValue)]))
    let parsed = try JSONValue.parse(out.text)
    #expect(parsed["success"] == .bool(true))
    #expect(parsed["data"]?["items"] == .array([.number(1), .number(2), .number(3)]))
  }

  @Test("JSON mode wraps error in failure result")
  func jsonError() throws {
    let (output, _, err) = makeOutput(json: true)
    output.error(RemiError(code: "TEST_ERROR", message: "Something broke", suggestion: "Fix it"))
    let parsed = try JSONValue.parse(err.text)
    #expect(parsed["success"] == .bool(false))
    #expect(parsed["error"]?["code"] == .string("TEST_ERROR"))
    #expect(parsed["error"]?["suggestion"] == .string("Fix it"))
  }

  @Test("JSON mode outputs message as JSON success")
  func jsonMessage() throws {
    let (output, out, _) = makeOutput(json: true)
    output.message("Created reminder", data: [("id", .string("abc123"))])
    let parsed = try JSONValue.parse(out.text)
    #expect(parsed["success"] == .bool(true))
    #expect(parsed["data"]?["message"] == .string("Created reminder"))
    #expect(parsed["data"]?["id"] == .string("abc123"))
  }

  // MARK: Ported from output.test.ts — human mode

  @Test("human mode outputs error to stderr with message")
  func humanError() {
    let (output, _, err) = makeOutput()
    output.error(RemiError(code: "TEST", message: "Oops"))
    #expect(err.text.contains("Oops"))
  }

  @Test("human mode outputs error with suggestion")
  func humanSuggestion() {
    let (output, _, err) = makeOutput()
    output.error(RemiError(code: "TEST", message: "Oops", suggestion: "Try again"))
    #expect(err.text.contains("Try again"))
  }

  @Test("human mode outputs success message with checkmark")
  func humanMessage() {
    let (output, out, _) = makeOutput()
    output.message("Done!")
    #expect(out.text.contains("Done!"))
    #expect(out.text == "✓ Done!\n")
  }

  // MARK: Additional behaviour

  @Test("JSON envelope is pretty-printed exactly like JSON.stringify(result, null, 2)")
  func jsonEnvelopeFormat() {
    let (output, out, _) = makeOutput(json: true)
    output.message("Created", data: [("id", .string("x")), ("message", .string("override"))])
    #expect(
      out.text == "{\n  \"success\": true,\n  \"data\": {\n    \"message\": \"override\",\n    \"id\": \"x\"\n  }\n}\n")
  }

  @Test("relative date labels")
  func relativeDates() {
    let (output, _, _) = makeOutput()
    #expect(output.formatRelativeDate("2026-10-22").text == "1d overdue")
    #expect(output.formatRelativeDate("2026-10-13").text == "10d overdue")
    #expect(output.formatRelativeDate("2026-10-23") == .init(text: "today", isOverdue: false, isToday: true))
    #expect(output.formatRelativeDate("2026-10-24").text == "tomorrow")
    #expect(output.formatRelativeDate("2026-10-30").text == "in 7d")
    #expect(output.formatRelativeDate("2026-10-31").text == "Oct 31")
    #expect(output.formatRelativeDate("2027-01-02").text == "Jan 2 2027")
  }

  @Test("colour detection follows chalk conventions")
  func colorDetection() {
    #expect(ColorLevel.detect(isTTY: false, environment: [:]) == .none)
    #expect(ColorLevel.detect(isTTY: true, environment: ["TERM": "xterm"]) == .basic)
    #expect(ColorLevel.detect(isTTY: true, environment: ["TERM": "xterm-256color"]) == .ansi256)
    #expect(ColorLevel.detect(isTTY: true, environment: ["COLORTERM": "truecolor"]) == .trueColor)
    #expect(ColorLevel.detect(isTTY: true, environment: ["NO_COLOR": "1"]) == .none)
    #expect(ColorLevel.detect(isTTY: false, environment: ["FORCE_COLOR": "3"]) == .trueColor)
    #expect(ColorLevel.detect(isTTY: true, environment: ["TERM": "dumb"]) == .none)
  }

  // MARK: Parity with remi's output.ts

  @Test("matches remi output.ts byte for byte", arguments: outputCases)
  func parity(_ testCase: OutputCase) {
    let (output, out, err) = makeOutput(json: testCase.json, verbose: testCase.verbose, color: testCase.color)
    render(testCase.name, output)
    #expect(out.text == testCase.stdout)
    #expect(err.text == testCase.stderr)
  }
}
