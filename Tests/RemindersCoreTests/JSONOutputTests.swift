import Foundation
import Testing

@testable import RemindersCore

/// Parsed JSON, compared structurally (key order and whitespace don't matter).
indirect enum JSONTree: Decodable, Equatable {
  case null, bool(Bool), number(Double), string(String), array([JSONTree]), object([String: JSONTree])

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONTree].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONTree].self))
    }
  }

  init(_ text: String) throws {
    self = try JSONDecoder().decode(JSONTree.self, from: Data(text.utf8))
  }

  subscript(key: String) -> JSONTree? {
    if case .object(let fields) = self { fields[key] } else { nil }
  }

  subscript(index: Int) -> JSONTree? {
    if case .array(let items) = self, items.indices.contains(index) { items[index] } else { nil }
  }
}

@Suite("JSON output")
struct JSONOutputTests {
  @Test("results are wrapped in a success envelope on stdout")
  func success() throws {
    let (console, output, errors) = makeConsole(json: true)
    console.show(Confirmation("Created reminder", id: "abc123"))
    #expect(errors.text.isEmpty)
    let json = try JSONTree(output.text)
    #expect(
      json
        == .object([
          "success": .bool(true), "data": .object(["message": .string("Created reminder"), "id": .string("abc123")]),
        ]))
    #expect(output.text.hasSuffix("}\n"))
  }

  @Test("errors are wrapped in a failure envelope on stderr; a missing suggestion is omitted")
  func failure() throws {
    let (console, output, errors) = makeConsole(json: true)
    console.report(RemindersError(.notImplemented, "Not yet"))
    #expect(output.text.isEmpty)
    #expect(
      try JSONTree(errors.text)
        == .object([
          "success": .bool(false),
          "error": .object(["code": .string("NOT_IMPLEMENTED"), "message": .string("Not yet")]),
        ]))
  }

  @Test("output is pretty-printed with sorted keys and unescaped slashes")
  func formatting() {
    let (console, output, _) = makeConsole(json: true)
    console.show(Confirmation("a/b"))
    #expect(output.text == "{\n  \"data\" : {\n    \"message\" : \"a/b\"\n  },\n  \"success\" : true\n}\n")
  }

  @Test("reminders keep their documented fields; absent ones are omitted")
  func reminders() throws {
    let (console, output, _) = makeConsole(json: true)
    console.show(ReminderListing(sampleReminders, heading: "x", layout: .list))
    let data = try #require(try JSONTree(output.text)["data"])
    #expect(
      data[0]
        == .object([
          "id": .string("A1"), "title": .string("Buy milk"), "isCompleted": .bool(false), "listID": .string("L1"),
          "listName": .string("Groceries"), "priority": .string("high"), "dueDate": .string("2026-10-23"),
          "notes": .string("Organic only, the big bottle from the shop round the corner please"),
          "section": .string("Dairy"), "isRecurring": .bool(false), "flagged": .bool(true),
        ]))
    #expect(data[1]?["recurrence"] == .string("monthly"))
    #expect(data[1]?["isRecurring"] == .bool(true))
    #expect(data[2]?["completionDate"] == .string("2026-10-22T08:30:00Z"))
    #expect(data[3]?["isRecurring"] == .bool(true))
    #expect(data[3]?["recurrence"] == nil)
    #expect(data[6]?["dueDate"] == nil)
  }

  @Test("lists and sections are plain arrays")
  func collections() throws {
    let (console, output, _) = makeConsole(json: true)
    console.show(ListOverview([ReminderList(id: "L", title: "Home", reminderCount: 3, overdueCount: 1)]))
    #expect(
      try JSONTree(output.text)["data"]
        == .array([
          .object([
            "id": .string("L"), "title": .string("Home"), "reminderCount": .number(3), "overdueCount": .number(1),
          ])
        ]))
  }
}
