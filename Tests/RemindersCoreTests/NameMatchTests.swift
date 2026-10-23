import Testing

@testable import RemindersCore

private let lists = ["Groceries / Shopping List", "Work", "Workouts", "Home"].enumerated().map {
  ReminderList(id: "L\($0.offset)", title: $0.element)
}

@Suite("Name matching")
struct NameMatchTests {
  @Test("exact beats case-insensitive beats substring")
  func preference() throws {
    #expect(try lists.resolve("Work").title == "Work")
    #expect(try lists.resolve("home").title == "Home")
    #expect(try lists.resolve("WORK").title == "Work")
    #expect(try lists.resolve("groceries").title == "Groceries / Shopping List")
    #expect(try lists.resolve("outs").title == "Workouts")
  }

  @Test("ambiguous substrings list the candidates")
  func ambiguous() {
    #expect(
      throws: RemindersError(
        .ambiguousReminder, "\"or\" matches multiple lists:\n  - Work\n  - Workouts",
        suggestion: "Be more specific, or use the full name")
    ) { try lists.resolve("or") }
  }

  @Test("no match suggests everything available")
  func noMatch() {
    #expect(
      throws: RemindersError(
        .listNotFound, "No list matching \"zzz\"",
        suggestion: "Available lists:\n  - Groceries / Shopping List\n  - Work\n  - Workouts\n  - Home")
    ) { try lists.resolve("zzz") }
    #expect(throws: RemindersError(.listNotFound, "No lists found")) { try [ReminderList]().resolve("x") }
  }

  @Test("sections report SECTION_NOT_FOUND")
  func sections() {
    let sections = [Section(id: "S1", displayName: "Dairy", listName: "Groceries", sortOrder: 0)]
    #expect(
      throws: RemindersError(
        .sectionNotFound, "No section matching \"meat\"", suggestion: "Available sections:\n  - Dairy")
    ) {
      try sections.resolve("meat")
    }
  }

  @Test("canonically equivalent names match (precomposed é = e + combining accent)")
  func canonicalEquivalence() throws {
    let cafes = [ReminderList(id: "1", title: "Caf\u{E9}")]
    #expect(try cafes.resolve("Cafe\u{301}").id == "1")
  }
}

private let reminders = [
  Reminder(id: "ABCD1234-0000", title: "Buy milk"),
  Reminder(id: "ABEF5678-0000", title: "buy milk and eggs"),
  Reminder(id: "CDEF0000-0000", title: "Call Bob"),
]

@Suite("Reminder lookup")
struct ReminderLookupTests {
  @Test("exact, then case-insensitive, then unique substring")
  func preference() throws {
    #expect(try reminders.find(title: "Buy milk", inList: "L").id == "ABCD1234-0000")
    #expect(try reminders.find(title: "BUY MILK AND EGGS", inList: "L").id == "ABEF5678-0000")
    #expect(try reminders.find(title: "bob", inList: "L").id == "CDEF0000-0000")
  }

  @Test("ambiguous and missing titles")
  func failures() {
    #expect(
      throws: RemindersError(
        .ambiguousReminder,
        "\"milk\" matches multiple reminders in \"L\":\n  - \"Buy milk\"\n  - \"buy milk and eggs\"",
        suggestion: "Be more specific, or use --id <prefix>")
    ) { try reminders.find(title: "milk", inList: "L") }
    #expect(
      throws: RemindersError(
        .reminderNotFound, "No reminder matching \"zzz\" in \"L\"",
        suggestion: "Use \"reminders list 'L'\" to see available reminders")
    ) { try reminders.find(title: "zzz", inList: "L") }
  }

  @Test("an ID prefix is case-insensitive and wins over the title")
  func idPrefix() throws {
    #expect(try reminders.find(title: "Call Bob", idPrefix: "abef", inList: "L").id == "ABEF5678-0000")
    #expect(throws: RemindersError(.reminderNotFound, "No reminder found with ID starting with \"ff\" in \"L\"")) {
      try reminders.find(title: "x", idPrefix: "ff", inList: "L")
    }
  }
}
