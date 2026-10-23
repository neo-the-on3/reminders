import Testing

@testable import RemindersCore

private func parse(_ text: String) throws(RemindersError) -> Recurrence { try Recurrence(parsing: text) }

@Suite("Recurrence")
struct RecurrenceTests {
  @Test("simple frequencies")
  func simple() throws {
    #expect(try parse("daily") == Recurrence(.daily))
    #expect(try parse("weekly") == Recurrence(.weekly))
    #expect(try parse("monthly") == Recurrence(.monthly))
    #expect(try parse("yearly") == Recurrence(.yearly))
  }

  @Test("every N units, and every unit")
  func every() throws {
    #expect(try parse("every 2 weeks") == Recurrence(.weekly, interval: 2))
    #expect(try parse("every 3 months") == Recurrence(.monthly, interval: 3))
    #expect(try parse("every 5 days") == Recurrence(.daily, interval: 5))
    #expect(try parse("every week") == Recurrence(.weekly))
    #expect(try parse("every month") == Recurrence(.monthly))
  }

  @Test("weekdays, full or abbreviated, separated by commas or spaces")
  func weekdays() throws {
    #expect(try parse("every 2 weeks on monday,friday") == Recurrence(.weekly, interval: 2, on: [.monday, .friday]))
    #expect(try parse("every week on mon,wed,fri").weekdays == [.monday, .wednesday, .friday])
    #expect(try parse("every 1 week on mon wed, fri").weekdays == [.monday, .wednesday, .friday])
    #expect(try parse("every day on sun").weekdays == [.sunday])
  }

  @Test("case and surrounding whitespace don't matter")
  func normalisation() throws {
    #expect(try parse("Daily") == Recurrence(.daily))
    #expect(try parse("EVERY 2 WEEKS") == Recurrence(.weekly, interval: 2))
    #expect(try parse("  daily  ") == Recurrence(.daily))
  }

  @Test("invalid rules explain what is accepted")
  func invalid() {
    #expect(
      throws: RemindersError(
        .invalidArgument, "Unknown frequency unit \"blobs\"", suggestion: "Use: day(s), week(s), month(s), year(s)")
    ) { try parse("every 2 blobs") }
    #expect(
      throws: RemindersError(
        .invalidArgument, "Cannot parse repeat rule \"Never\"",
        suggestion: "Examples: \"daily\", \"weekly\", \"every 2 weeks\", \"every 3 months\"")
    ) { try parse("Never") }
    #expect(
      throws: RemindersError(
        .invalidArgument, "Unknown day \"funday\"",
        suggestion: "Use: monday, tuesday, wednesday, thursday, friday, saturday, sunday (or mon, tue, etc.)")
    ) { try parse("every week on funday") }
    for text in ["", "every 2", "every 2 weeks on", "every 2 weeks extra"] {
      #expect(throws: RemindersError.self) { try parse(text) }
    }
  }

  @Test("describes itself the way it is shown")
  func description() {
    #expect(Recurrence(.daily).description == "daily")
    #expect(Recurrence(.yearly).description == "yearly")
    #expect(Recurrence(.weekly, interval: 2).description == "every 2 weeks")
    #expect(Recurrence(.weekly, on: [.monday, .friday]).description == "weekly on Mon, Fri")
    #expect(Recurrence(.daily, on: [.monday]).description == "daily")
  }
}
