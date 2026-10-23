import Foundation
import Testing

@testable import RemindersCore

struct DateReferenceCase: Sendable, CustomTestStringConvertible {
  let reference: String
  let input: String
  let expected: String?

  init(_ reference: String, _ input: String, _ expected: String?) {
    self.reference = reference
    self.input = input
    self.expected = expected
  }

  var testDescription: String { "\(input.debugDescription) @ \(reference)" }
}

/// Phrases where DueDateParser deliberately differs from the reference parser (documented in the README).
let intentionalReferenceDeviations: [String: String] = [
  // The reference only matches the trailing "tomorrow" (+1 day); "day after tomorrow" means +2.
  "day after tomorrow": "+2 days",
  // The reference doesn't know the common "tues" abbreviation.
  "tues": "accepted",
  // The reference accepts "this week" with surprising results (the next day).
  "this week": "rejected",
  // The reference rejects "secs" (only matters across midnight).
  "in 3 secs": "accepted",
]

private let utc = TimeZone(identifier: "UTC")!

private func instant(_ iso: String) -> Date {
  ISO8601DateFormatter().date(from: iso)!
}

private func parse(_ input: String, at reference: String, in zone: TimeZone = utc) throws(RemindersError) -> String {
  try DueDateParser(clock: DayClock(now: instant(reference), timeZone: zone)).parse(input).description
}

@Suite("DueDateParser")
struct DueDateParserTests {
  @Test("YYYY-MM-DD passes through, trimmed")
  func isoDates() throws {
    #expect(try parse("2026-04-15", at: "2026-10-23T10:00:00Z") == "2026-04-15")
    #expect(try parse("  2026-12-31  ", at: "2026-10-23T10:00:00Z") == "2026-12-31")
  }

  @Test("impossible YYYY-MM-DD dates are rejected")
  func invalidISODates() {
    #expect(
      throws: RemindersError(
        .invalidArgument, "Invalid date \"2026-02-30\"", suggestion: "Use a real calendar date (YYYY-MM-DD)")
    ) { try parse("2026-02-30", at: "2026-10-23T10:00:00Z") }
  }

  @Test("relative phrases use the clock's instant and time zone")
  func referenceAndZone() throws {
    let now = "2026-10-23T20:00:00Z"  // Fri 20:00 UTC = Sat 01:30 in Kolkata
    #expect(try parse("today", at: now) == "2026-10-23")
    #expect(try parse("today", at: now, in: TimeZone(identifier: "Asia/Kolkata")!) == "2026-10-24")
    #expect(try parse("tomorrow", at: now, in: TimeZone(identifier: "America/Los_Angeles")!) == "2026-10-24")
    #expect(try parse("next friday", at: now) == "2026-10-30")
  }

  @Test("month arithmetic rolls day overflow into the next month (Jan 31 + 1 month = Mar 2 or 3)")
  func monthOverflow() throws {
    #expect(try parse("in 1 month", at: "2027-01-31T10:00:00Z") == "2027-03-03")
    #expect(try parse("next month", at: "2028-01-31T10:00:00Z") == "2028-03-02")
  }

  @Test("unparseable input carries a suggestion")
  func errors() {
    #expect(
      throws: RemindersError(
        .invalidArgument, "Cannot parse date \"someday\"",
        suggestion: "Use YYYY-MM-DD or natural language: \"tomorrow\", \"next tuesday\", \"in 3 days\"")
    ) { try parse("someday", at: "2026-10-23T10:00:00Z") }
    #expect(throws: RemindersError.self) { try parse("", at: "2026-10-23T10:00:00Z") }
  }

  @Test("intentional deviations from the reference parser")
  func deviations() throws {
    let now = "2026-10-23T10:00:00Z"  // Friday
    #expect(try parse("day after tomorrow", at: now) == "2026-10-25")
    #expect(try parse("tues", at: now) == "2026-10-27")
    #expect(throws: RemindersError.self) { try parse("this week", at: now) }
  }

  @Test("matches the reference parser", arguments: dateReferenceCases)
  func reference(_ testCase: DateReferenceCase) throws {
    guard intentionalReferenceDeviations[testCase.input] == nil else { return }
    if let expected = testCase.expected {
      #expect(try parse(testCase.input, at: testCase.reference) == expected)
    } else {
      #expect(throws: RemindersError.self) { try parse(testCase.input, at: testCase.reference) }
    }
  }
}

@Suite("CalendarDay")
struct CalendarDayTests {
  @Test("parses and prints YYYY-MM-DD, rejecting impossible days")
  func roundTrip() {
    #expect(CalendarDay("2028-02-29")?.description == "2028-02-29")
    #expect(CalendarDay("2027-02-29") == nil)
    #expect(CalendarDay("2026-1-01") == nil)
    #expect(CalendarDay("２０２６-01-01") == nil)
    #expect(CalendarDay(year: 987, month: 3, day: 4)?.description == "0987-03-04")
  }

  @Test("orders chronologically and counts days from today")
  func arithmetic() throws {
    let day = try #require(CalendarDay("2026-12-31"))
    #expect(day.adding(days: 1).description == "2027-01-01")
    #expect(day < day.adding(days: 1))
    let clock = DayClock(now: instant("2026-10-23T23:30:00Z"), timeZone: utc)
    #expect(clock.days(until: try #require(CalendarDay("2026-10-22"))) == -1)
    #expect(clock.days(until: try #require(CalendarDay("2026-11-23"))) == 31)
  }

  @Test("encodes as a YYYY-MM-DD string")
  func coding() throws {
    let data = try JSONEncoder().encode([CalendarDay("2026-04-15")])
    #expect(String(bytes: data, encoding: .utf8) == #"["2026-04-15"]"#)
    #expect(try JSONDecoder().decode([CalendarDay].self, from: data) == [CalendarDay("2026-04-15")!])
  }
}
