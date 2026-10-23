// Ported from remi src/core/recurrence.ts (MIT, Matthew O'Riordan).
//
// Parse human-friendly --repeat strings into EKRecurrenceRule parameters.
//
// Supported formats:
//   "daily", "weekly", "monthly", "yearly"
//   "every 2 weeks", "every 3 months"
//   "every 2 weeks on monday,friday"

/// Recurrence rule parameters, as passed to the EventKit layer.
public struct RecurrenceParams: Equatable, Sendable {
  /// `DAILY`, `WEEKLY`, `MONTHLY` or `YEARLY`.
  public var rruleFreq: String
  public var rruleInterval: Int
  /// Days of the week, EventKit numbering (1 = Sunday … 7 = Saturday).
  public var rruleDays: [Int]?

  public init(rruleFreq: String, rruleInterval: Int, rruleDays: [Int]? = nil) {
    self.rruleFreq = rruleFreq
    self.rruleInterval = rruleInterval
    self.rruleDays = rruleDays
  }
}

private let dayMap: [String: Int] = [
  "sunday": 1, "sun": 1,
  "monday": 2, "mon": 2,
  "tuesday": 3, "tue": 3,
  "wednesday": 4, "wed": 4,
  "thursday": 5, "thu": 5,
  "friday": 6, "fri": 6,
  "saturday": 7, "sat": 7,
]

private let freqAliases: [String: String] = [
  "daily": "DAILY", "weekly": "WEEKLY", "monthly": "MONTHLY", "yearly": "YEARLY",
  "day": "DAILY", "days": "DAILY",
  "week": "WEEKLY", "weeks": "WEEKLY",
  "month": "MONTHLY", "months": "MONTHLY",
  "year": "YEARLY", "years": "YEARLY",
]

/// Parse a `--repeat` value. Throws ``RemiCommandError`` with code `INVALID_ARGUMENT` on bad input.
public func parseRepeat(_ input: String) throws(RemiCommandError) -> RecurrenceParams {
  let s = input.jsTrimmed.jsLowercased

  // Simple: "daily", "weekly", "monthly", "yearly"
  if let freq = freqAliases[s] {
    return RecurrenceParams(rruleFreq: freq, rruleInterval: 1)
  }

  // "every N <unit>" with optional "on <days>"   — /^every\s+(\d+)\s+(\w+?)(?:\s+on\s+(.+))?$/
  let everyN = #/^every\s+(\d+)\s+(\w+?)(?:\s+on\s+(.+))?$/#.asciiOnlyDigits().asciiOnlyWordCharacters()
  if let match = s.wholeMatch(of: everyN) {
    // parseInt saturates rather than overflowing for absurdly large numbers.
    let interval = Int(match.1) ?? Int.max
    let unit = String(match.2)
    guard let freq = freqAliases[unit] else {
      throw RemiCommandError(
        .invalidArgument, "Unknown frequency unit \"\(unit)\"", suggestion: "Use: day(s), week(s), month(s), year(s)")
    }
    var result = RecurrenceParams(rruleFreq: freq, rruleInterval: interval)
    if let days = match.3 {
      result.rruleDays = try parseDays(String(days))
    }
    return result
  }

  // "every <unit>" (no number = interval 1)   — /^every\s+(\w+?)(?:\s+on\s+(.+))?$/
  let every = #/^every\s+(\w+?)(?:\s+on\s+(.+))?$/#.asciiOnlyDigits().asciiOnlyWordCharacters()
  if let match = s.wholeMatch(of: every), let freq = freqAliases[String(match.1)] {
    var result = RecurrenceParams(rruleFreq: freq, rruleInterval: 1)
    if let days = match.2 {
      result.rruleDays = try parseDays(String(days))
    }
    return result
  }

  throw RemiCommandError(
    .invalidArgument, "Cannot parse repeat rule \"\(input)\"",
    suggestion: "Examples: \"daily\", \"weekly\", \"every 2 weeks\", \"every 3 months\"")
}

private func parseDays(_ input: String) throws(RemiCommandError) -> [Int] {
  // input.split(/[,\s]+/)
  let days = input.unicodeScalars.split(whereSeparator: { $0 == "," || $0.isJSWhitespace })
    .map { String($0).jsTrimmed.jsLowercased }
  var result: [Int] = []
  for day in days where !day.isEmpty {
    guard let number = dayMap[day] else {
      throw RemiCommandError(
        .invalidArgument, "Unknown day \"\(day)\"",
        suggestion: "Use: monday, tuesday, wednesday, thursday, friday, saturday, sunday (or mon, tue, etc.)")
    }
    result.append(number)
  }
  return result
}
