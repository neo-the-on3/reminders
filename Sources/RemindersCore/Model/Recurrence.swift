import Foundation

/// How a reminder repeats: every `interval` days, weeks, months or years, optionally on given weekdays.
public struct Recurrence: Hashable, Sendable {
  public enum Frequency: String, CaseIterable, Hashable, Sendable {
    case daily, weekly, monthly, yearly

    var unit: String {
      switch self {
      case .daily: "day"
      case .weekly: "week"
      case .monthly: "month"
      case .yearly: "year"
      }
    }
  }

  /// Days of the week, numbered like EventKit and `Calendar` (1 = Sunday … 7 = Saturday).
  public enum Weekday: Int, CaseIterable, Hashable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var shortName: String {
      ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][rawValue - 1]
    }
  }

  public var frequency: Frequency
  public var interval: Int
  public var weekdays: [Weekday]
  /// Last day the reminder repeats, if any.
  public var end: CalendarDay?

  public init(_ frequency: Frequency, interval: Int = 1, on weekdays: [Weekday] = [], end: CalendarDay? = nil) {
    self.frequency = frequency
    self.interval = interval
    self.weekdays = weekdays
    self.end = end
  }
}

extension Recurrence: CustomStringConvertible {
  /// Human-readable form: "daily", "weekly", "every 2 weeks", "weekly on Mon, Fri".
  public var description: String {
    var text: String
    if interval == 1 {
      text = frequency.rawValue
    } else {
      text = "every \(interval) \(frequency.unit)s"
    }
    if frequency == .weekly && !weekdays.isEmpty {
      text += " on " + weekdays.map(\.shortName).joined(separator: ", ")
    }
    return text
  }
}

// MARK: - Parsing `--repeat`

extension Recurrence {
  /// Parses a `--repeat` value: `daily`, `weekly`, `monthly`, `yearly`, `every 2 weeks`, `every month`,
  /// `every 2 weeks on monday,friday` (case-insensitive).
  public init(parsing input: String) throws(RemindersError) {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    if let frequency = Self.frequencyWords[text] {
      self.init(frequency)
      return
    }

    let everyN = #/every\s+(\d+)\s+(\w+?)(?:\s+on\s+(.+))?/#.asciiOnlyDigits().asciiOnlyWordCharacters()
    if let match = text.wholeMatch(of: everyN) {
      let unit = String(match.2)
      guard let frequency = Self.frequencyWords[unit] else {
        throw RemindersError(
          .invalidArgument, "Unknown frequency unit \"\(unit)\"", suggestion: "Use: day(s), week(s), month(s), year(s)")
      }
      self.init(frequency, interval: Int(match.1) ?? .max, on: try Self.weekdays(in: match.3))
      return
    }

    let every = #/every\s+(\w+?)(?:\s+on\s+(.+))?/#.asciiOnlyWordCharacters()
    if let match = text.wholeMatch(of: every), let frequency = Self.frequencyWords[String(match.1)] {
      self.init(frequency, on: try Self.weekdays(in: match.2))
      return
    }

    throw RemindersError(
      .invalidArgument, "Cannot parse repeat rule \"\(input)\"",
      suggestion: "Examples: \"daily\", \"weekly\", \"every 2 weeks\", \"every 3 months\"")
  }

  private static let frequencyWords: [String: Frequency] = [
    "daily": .daily, "day": .daily, "days": .daily,
    "weekly": .weekly, "week": .weekly, "weeks": .weekly,
    "monthly": .monthly, "month": .monthly, "months": .monthly,
    "yearly": .yearly, "year": .yearly, "years": .yearly,
  ]

  private static let weekdayWords: [String: Weekday] = {
    var words: [String: Weekday] = [:]
    for weekday in Weekday.allCases {
      words[weekday.shortName.lowercased()] = weekday
      words["\(weekday)"] = weekday
    }
    return words
  }()

  private static func weekdays(in list: Substring?) throws(RemindersError) -> [Weekday] {
    guard let list else { return [] }
    var result: [Weekday] = []
    for word in list.split(whereSeparator: { $0 == "," || $0.isWhitespace }) {
      guard let weekday = weekdayWords[String(word)] else {
        throw RemindersError(
          .invalidArgument, "Unknown day \"\(word)\"",
          suggestion: "Use: monday, tuesday, wednesday, thursday, friday, saturday, sunday (or mon, tue, etc.)")
      }
      result.append(weekday)
    }
    return result
  }
}
