// Ported from remi tests/unit/recurrence.test.ts.

import Testing

@testable import RemiCore

@Suite("parseRepeat")
struct RecurrenceTests {
  @Test("parses simple frequencies")
  func simple() throws {
    #expect(try parseRepeat("daily") == RecurrenceParams(rruleFreq: "DAILY", rruleInterval: 1))
    #expect(try parseRepeat("weekly") == RecurrenceParams(rruleFreq: "WEEKLY", rruleInterval: 1))
    #expect(try parseRepeat("monthly") == RecurrenceParams(rruleFreq: "MONTHLY", rruleInterval: 1))
    #expect(try parseRepeat("yearly") == RecurrenceParams(rruleFreq: "YEARLY", rruleInterval: 1))
  }

  @Test("parses 'every N unit' format")
  func everyN() throws {
    #expect(try parseRepeat("every 2 weeks") == RecurrenceParams(rruleFreq: "WEEKLY", rruleInterval: 2))
    #expect(try parseRepeat("every 3 months") == RecurrenceParams(rruleFreq: "MONTHLY", rruleInterval: 3))
    #expect(try parseRepeat("every 5 days") == RecurrenceParams(rruleFreq: "DAILY", rruleInterval: 5))
  }

  @Test("parses 'every unit' (no number = interval 1)")
  func everyUnit() throws {
    #expect(try parseRepeat("every week") == RecurrenceParams(rruleFreq: "WEEKLY", rruleInterval: 1))
    #expect(try parseRepeat("every month") == RecurrenceParams(rruleFreq: "MONTHLY", rruleInterval: 1))
  }

  @Test("parses day-of-week specifiers")
  func days() throws {
    let result = try parseRepeat("every 2 weeks on monday,friday")
    #expect(result.rruleFreq == "WEEKLY")
    #expect(result.rruleInterval == 2)
    #expect(result.rruleDays == [2, 6])
  }

  @Test("handles abbreviated day names")
  func abbreviated() throws {
    #expect(try parseRepeat("every week on mon,wed,fri").rruleDays == [2, 4, 6])
  }

  @Test("is case-insensitive")
  func caseInsensitive() throws {
    #expect(try parseRepeat("Daily") == RecurrenceParams(rruleFreq: "DAILY", rruleInterval: 1))
    #expect(try parseRepeat("EVERY 2 WEEKS") == RecurrenceParams(rruleFreq: "WEEKLY", rruleInterval: 2))
  }

  @Test("trims whitespace")
  func trims() throws {
    #expect(try parseRepeat("  daily  ") == RecurrenceParams(rruleFreq: "DAILY", rruleInterval: 1))
  }

  @Test("throws on invalid input")
  func invalid() {
    #expect(throws: RemiCommandError.self) { try parseRepeat("never") }
    #expect(throws: RemiCommandError.self) { try parseRepeat("every 2 blobs") }
    #expect(throws: RemiCommandError.self) { try parseRepeat("") }
  }

  @Test("throws on invalid day names")
  func invalidDay() {
    #expect(throws: RemiCommandError.self) { try parseRepeat("every week on funday") }
  }

  // MARK: Additional behaviour

  @Test("day lists accept spaces and mixed separators")
  func separators() throws {
    #expect(try parseRepeat("every 1 week on mon wed, fri").rruleDays == [2, 4, 6])
    #expect(try parseRepeat("every day on sun").rruleDays == [1])
  }

  @Test("error messages match remi")
  func messages() {
    #expect(
      throws: RemiCommandError(
        .invalidArgument, "Unknown frequency unit \"blobs\"", suggestion: "Use: day(s), week(s), month(s), year(s)")
    ) { try parseRepeat("every 2 blobs") }
    #expect(
      throws: RemiCommandError(
        .invalidArgument, "Cannot parse repeat rule \"Never\"",
        suggestion: "Examples: \"daily\", \"weekly\", \"every 2 weeks\", \"every 3 months\"")
    ) { try parseRepeat("Never") }
    #expect(
      throws: RemiCommandError(
        .invalidArgument, "Unknown day \"funday\"",
        suggestion: "Use: monday, tuesday, wednesday, thursday, friday, saturday, sunday (or mon, tue, etc.)")
    ) { try parseRepeat("every week on funday") }
  }

  @Test("'every N' without a unit word and dangling 'on' are rejected")
  func edgeCases() {
    #expect(throws: RemiCommandError.self) { try parseRepeat("every 2") }
    #expect(throws: RemiCommandError.self) { try parseRepeat("every 2 weeks on") }
    #expect(throws: RemiCommandError.self) { try parseRepeat("every 2 weeks extra") }
  }
}
