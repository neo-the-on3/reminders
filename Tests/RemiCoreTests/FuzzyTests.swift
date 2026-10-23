// remi has no unit tests for fuzzy.ts / lookup.ts; these pin down the ported behaviour.

import Testing

@testable import RemiCore

private let lists = ["Groceries / Shopping List", "Work", "Workouts", "Home"]

@Suite("fuzzyFind")
struct FuzzyTests {
  @Test("exact match wins over case-insensitive and substring")
  func exact() throws {
    #expect(try fuzzyFind("Work", in: lists, name: { $0 }, itemType: "list") == "Work")
  }

  @Test("case-insensitive exact match")
  func caseInsensitive() throws {
    #expect(try fuzzyFind("home", in: lists, name: { $0 }, itemType: "list") == "Home")
    #expect(try fuzzyFind("WORK", in: lists, name: { $0 }, itemType: "list") == "Work")
  }

  @Test("unique substring match")
  func substring() throws {
    #expect(try fuzzyFind("groceries", in: lists, name: { $0 }, itemType: "list") == "Groceries / Shopping List")
    #expect(try fuzzyFind("outs", in: lists, name: { $0 }, itemType: "list") == "Workouts")
  }

  @Test("ambiguous substring lists candidates")
  func ambiguous() {
    #expect(
      throws: RemiCommandError(
        .ambiguousReminder, "\"or\" matches multiple lists:\n  - Work\n  - Workouts",
        suggestion: "Be more specific, or use the full name")
    ) { try fuzzyFind("or", in: lists, name: { $0 }, itemType: "list") }
  }

  @Test("no match suggests all items")
  func noMatch() {
    #expect(
      throws: RemiCommandError(
        .listNotFound, "No section matching \"zzz\"",
        suggestion: "Available sections:\n  - Groceries / Shopping List\n  - Work\n  - Workouts\n  - Home")
    ) { try fuzzyFind("zzz", in: lists, name: { $0 }, itemType: "section") }
  }

  @Test("empty collection")
  func empty() {
    #expect(throws: RemiCommandError(.listNotFound, "No lists found")) {
      try fuzzyFind("x", in: [String](), name: { $0 }, itemType: "list")
    }
  }

  @Test("comparison is by code units, like JavaScript (é precomposed ≠ e + combining accent)")
  func codeUnits() throws {
    let items = ["Caf\u{E9}", "Cafe\u{301} Bar"]
    #expect(try fuzzyFind("Caf\u{E9}", in: items, name: { $0 }, itemType: "list") == "Caf\u{E9}")
    #expect(try fuzzyFind("Cafe\u{301}", in: items, name: { $0 }, itemType: "list") == "Cafe\u{301} Bar")
  }
}

private let reminders = [
  Reminder(id: "ABCD1234-0000", title: "Buy milk"),
  Reminder(id: "ABEF5678-0000", title: "buy milk and eggs"),
  Reminder(id: "CDEF0000-0000", title: "Call Bob"),
]

@Suite("findReminder")
struct LookupTests {
  @Test("exact, then case-insensitive, then unique substring")
  func priority() throws {
    #expect(try findReminder(in: reminders, listName: "L", title: "Buy milk").id == "ABCD1234-0000")
    #expect(try findReminder(in: reminders, listName: "L", title: "BUY MILK AND EGGS").id == "ABEF5678-0000")
    #expect(try findReminder(in: reminders, listName: "L", title: "bob").id == "CDEF0000-0000")
  }

  @Test("ambiguous substring")
  func ambiguous() {
    #expect(
      throws: RemiCommandError(
        .ambiguousReminder,
        "\"milk\" matches multiple reminders in \"L\":\n  - \"Buy milk\"\n  - \"buy milk and eggs\"",
        suggestion: "Be more specific, or use --id <prefix>")
    ) { try findReminder(in: reminders, listName: "L", title: "milk") }
  }

  @Test("not found")
  func notFound() {
    #expect(
      throws: RemiCommandError(
        .reminderNotFound, "No reminder matching \"zzz\" in \"L\"",
        suggestion: "Use \"remi list 'L'\" to see available reminders")
    ) { try findReminder(in: reminders, listName: "L", title: "zzz") }
  }

  @Test("ID prefix match is case-insensitive and takes precedence over title")
  func idPrefix() throws {
    #expect(try findReminder(in: reminders, listName: "L", title: "Call Bob", id: "abef").id == "ABEF5678-0000")
    #expect(throws: RemiCommandError(.reminderNotFound, "No reminder found with ID starting with \"ff\" in \"L\"")) {
      try findReminder(in: reminders, listName: "L", title: "x", id: "ff")
    }
  }
}
