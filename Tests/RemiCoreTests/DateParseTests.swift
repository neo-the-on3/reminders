// Ported from remi tests/unit/dateparse.test.ts, plus chrono-node parity cases.

import Foundation
import Testing

@testable import RemiCore

struct ChronoCase: Sendable, CustomTestStringConvertible {
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

/// Inputs where the port intentionally differs from chrono-node (documented in README).
let intentionalChronoDeviations: [String: String] = [
  // chrono only matches the trailing "tomorrow" (+1 day); "day after tomorrow" means +2.
  "day after tomorrow": "+2 days",
  // chrono doesn't know the common "tues" abbreviation; the port accepts it.
  "tues": "accepted",
  // chrono accepts "this week" with surprising results (the next day); the port rejects it.
  "this week": "rejected",
  // chrono rejects "secs"; the port accepts it as seconds (only matters across midnight).
  "in 3 secs": "accepted",
]

private let utc = TimeZone(identifier: "UTC")!

private func reference(_ iso: String) -> Date {
  let formatter = ISO8601DateFormatter()
  return formatter.date(from: iso)!
}

@Suite("parseDate")
struct DateParseTests {
  // MARK: Ported from dateparse.test.ts

  @Test("passes through YYYY-MM-DD format")
  func passesThroughISO() throws {
    #expect(try parseDate("2026-04-15") == "2026-04-15")
    #expect(try parseDate("2026-12-31") == "2026-12-31")
  }

  @Test("parses 'tomorrow'")
  func tomorrow() throws {
    let result = try parseDate("tomorrow")
    #expect(isISODateString(result))
    #expect(result > formatYMDToday())
  }

  @Test("parses 'in 3 days'")
  func inThreeDays() throws {
    #expect(isISODateString(try parseDate("in 3 days")))
  }

  @Test("parses 'next friday'")
  func nextFriday() throws {
    let result = try parseDate("next friday")
    #expect(isISODateString(result))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let parts = result.split(separator: "-").map { Int($0)! }
    let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    #expect(calendar.component(.weekday, from: date) == 6)  // Friday
  }

  @Test("trims whitespace")
  func trims() throws {
    #expect(try parseDate("  2026-04-15  ") == "2026-04-15")
  }

  @Test("throws on unparseable input")
  func throwsOnGarbage() {
    #expect(throws: RemiCommandError.self) { try parseDate("not a date") }
    #expect(throws: RemiCommandError.self) { try parseDate("") }
  }

  @Test("error carries remi's code, message and suggestion")
  func errorShape() {
    #expect(
      throws: RemiCommandError(
        .invalidArgument, "Cannot parse date \"someday\"",
        suggestion: "Use YYYY-MM-DD or natural language: \"tomorrow\", \"next tuesday\", \"in 3 days\"")
    ) { try parseDate("someday") }
  }

  // MARK: Fixed-reference behaviour

  @Test("relative dates use the reference instant and time zone")
  func referenceAndZone() throws {
    let now = reference("2026-10-23T20:00:00Z")  // Fri 20:00 UTC = Sat 01:30 in Kolkata
    #expect(try parseDate("today", now: now, timeZone: utc) == "2026-10-23")
    #expect(try parseDate("today", now: now, timeZone: TimeZone(identifier: "Asia/Kolkata")!) == "2026-10-24")
    #expect(try parseDate("tomorrow", now: now, timeZone: TimeZone(identifier: "America/Los_Angeles")!) == "2026-10-24")
  }

  @Test("month arithmetic overflows like JavaScript Date (Jan 31 + 1 month = Mar 2 or 3)")
  func monthOverflow() throws {
    #expect(try parseDate("in 1 month", now: reference("2027-01-31T10:00:00Z"), timeZone: utc) == "2027-03-03")
    #expect(try parseDate("next month", now: reference("2028-01-31T10:00:00Z"), timeZone: utc) == "2028-03-02")
  }

  @Test("intentional deviations from chrono-node")
  func deviations() throws {
    let now = reference("2026-10-23T10:00:00Z")  // Friday
    #expect(try parseDate("day after tomorrow", now: now, timeZone: utc) == "2026-10-25")
    #expect(try parseDate("tues", now: now, timeZone: utc) == "2026-10-27")
    #expect(throws: RemiCommandError.self) { try parseDate("this week", now: now, timeZone: utc) }
  }

  // MARK: chrono-node parity

  @Test("matches chrono-node 2.9 (forwardDate) on reference cases", arguments: chronoCases)
  func chronoParity(_ testCase: ChronoCase) throws {
    if intentionalChronoDeviations[testCase.input] != nil { return }
    let now = reference(testCase.reference)
    if let expected = testCase.expected {
      #expect(try parseDate(testCase.input, now: now, timeZone: utc) == expected)
    } else {
      #expect(throws: RemiCommandError.self) { try parseDate(testCase.input, now: now, timeZone: utc) }
    }
  }
}

private func formatYMDToday() -> String {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = .current
  let c = calendar.dateComponents([.year, .month, .day], from: Date())
  return formatYMD(c.year!, c.month!, c.day!)
}
