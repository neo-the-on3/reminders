// Ported from remi src/core/dateparse.ts (MIT, Matthew O'Riordan).
//
// Date parsing: supports YYYY-MM-DD and natural language ("next tuesday", "in 3 days").
// Returns YYYY-MM-DD, which is what the EventKit layer expects.
//
// remi delegates natural language to chrono-node (`chrono.parse(text, new Date(), { forwardDate: true })`
// and takes the first result). There is no chrono equivalent for Swift, so this file implements the
// English subset remi documents and that users realistically type, reproducing chrono-node 2.9's
// results (including its forward-date rules). Like chrono, the first date expression found anywhere in
// the input wins, so "by friday" and "buy milk tomorrow" work. See Tests/RemiCoreTests/DateParseTests.swift
// for the reference cases, which were generated from chrono-node itself.

import Foundation

/// Parse a due date into `YYYY-MM-DD`.
/// - Parameters:
///   - input: `YYYY-MM-DD` (passed through unchanged) or a natural-language expression.
///   - now: reference instant ("today").
///   - timeZone: zone that defines the local calendar day (the Gregorian calendar is always used, as in JS).
public func parseDate(_ input: String, now: Date = Date(), timeZone: TimeZone = .current) throws(RemiCommandError)
  -> String
{
  let trimmed = input.jsTrimmed

  // Already YYYY-MM-DD: pass through (no validation, exactly like remi)
  if isISODateString(trimmed) { return trimmed }

  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = timeZone
  if let date = NaturalDateParser(now: now, calendar: calendar).parse(trimmed) {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return formatYMD(c.year!, c.month!, c.day!)
  }

  throw RemiCommandError(
    .invalidArgument, "Cannot parse date \"\(input)\"",
    suggestion: "Use YYYY-MM-DD or natural language: \"tomorrow\", \"next tuesday\", \"in 3 days\"")
}

/// `/^\d{4}-\d{2}-\d{2}$/`
func isISODateString(_ s: String) -> Bool {
  let bytes = Array(s.utf8)
  guard bytes.count == 10 else { return false }
  for (index, byte) in bytes.enumerated() {
    if index == 4 || index == 7 {
      if byte != UInt8(ascii: "-") { return false }
    } else if !(UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) {
      return false
    }
  }
  return true
}

func formatYMD(_ year: Int, _ month: Int, _ day: Int) -> String {
  func pad(_ value: Int, _ width: Int) -> String {
    let s = String(value)
    return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
  }
  return "\(year < 0 ? "-" : "")\(pad(abs(year), 4))-\(pad(month, 2))-\(pad(day, 2))"
}

// MARK: - Natural language

private struct TimeOfDay: Equatable {
  var hour: Int
  var minute: Int
  var isMidnight: Bool { hour == 0 && minute == 0 }
}

private enum DurationUnit {
  case second, minute, hour, day, week, month, year
}

private struct NaturalDateParser {
  let now: Date
  let calendar: Calendar

  // MARK: Entry point

  /// Like chrono: find the earliest date expression in the text (longest at that position).
  func parse(_ text: String) -> Date? {
    let tokens = tokenize(text)
    guard !tokens.isEmpty else { return nil }
    for start in 0..<tokens.count {
      for end in stride(from: tokens.count, to: start, by: -1) {
        // chrono matches "feb 30" / "31 sep" as one (invalid) date; it never falls back to the bare month
        if end - start == 1, Self.monthNumber(tokens[start]) != nil,
          (end < tokens.count && tokens[end].first?.isASCIIDigit == true)
            || (start > 0 && tokens[start - 1].first?.isASCIIDigit == true)
        {
          continue
        }
        if let date = parsePhrase(Array(tokens[start..<end])) { return date }
      }
    }
    return nil
  }

  private func tokenize(_ text: String) -> [String] {
    let lowered = text.lowercased().replacingOccurrences(of: ",", with: " ")
    return lowered.unicodeScalars.split(whereSeparator: { $0.isJSWhitespace }).map { String($0) }
  }

  private func parsePhrase(_ t: [String]) -> Date? {
    if let date = parseDatePart(t, time: nil) { return date }
    if let time = parseTimePart(t) { return timeOnly(time) }
    guard t.count >= 2 else { return nil }
    for split in 1..<t.count {
      // <date> [at|@] <time>      e.g. "tomorrow 9am", "next monday at 9am", "in 3 days at 5pm"
      var timeTokens = Array(t[split...])
      if let first = timeTokens.first, first == "at" || first == "@" { timeTokens.removeFirst() }
      if !timeTokens.isEmpty, let time = parseTimePart(timeTokens),
        let date = parseDatePart(Array(t[..<split]), time: time)
      {
        return date
      }
      // <time> [on] <date>        e.g. "5pm friday", "noon tomorrow"
      var dateTokens = Array(t[split...])
      if dateTokens.first == "on" { dateTokens.removeFirst() }
      if !dateTokens.isEmpty, let time = parseTimePart(Array(t[..<split])),
        let date = parseDatePart(dateTokens, time: time)
      {
        return date
      }
    }
    return nil
  }

  // MARK: Helpers

  private var startOfToday: Date { calendar.startOfDay(for: now) }

  private func day(_ offset: Int) -> Date {
    calendar.date(byAdding: .day, value: offset, to: startOfToday)!
  }

  private var nowMinutes: Int {
    let c = calendar.dateComponents([.hour, .minute], from: now)
    return c.hour! * 60 + c.minute!
  }

  private var nowSecondsOfDay: Double {
    now.timeIntervalSince(startOfToday)
  }

  /// chrono weekday numbering: 0 = Sunday … 6 = Saturday.
  private var refWeekday: Int { calendar.component(.weekday, from: now) - 1 }

  /// A bare time: today if still ahead, otherwise tomorrow (forwardDate). Midnight is always tomorrow.
  private func timeOnly(_ time: TimeOfDay) -> Date {
    if time.isMidnight { return day(1) }
    let target = Double(time.hour * 3600 + time.minute * 60)
    return target < nowSecondsOfDay ? day(1) : day(0)
  }

  // MARK: Time of day

  private func parseTimePart(_ tokens: [String]) -> TimeOfDay? {
    var t = tokens
    if let first = t.first, first == "at" || first == "@" { t.removeFirst() }
    guard !t.isEmpty, t.count <= 2 else { return nil }
    let s = t.joined()  // "9 am" -> "9am"
    switch s {
    case "noon", "midday": return TimeOfDay(hour: 12, minute: 0)
    case "midnight": return TimeOfDay(hour: 0, minute: 0)
    case "morning": return TimeOfDay(hour: 6, minute: 0)
    case "afternoon": return TimeOfDay(hour: 15, minute: 0)
    case "evening": return TimeOfDay(hour: 20, minute: 0)
    case "night": return TimeOfDay(hour: 22, minute: 0)
    default: break
    }
    var body = Substring(s)
    var meridiem: String?
    for suffix in ["a.m.", "p.m.", "am", "pm", "a", "p"] where body.hasSuffix(suffix) {
      meridiem = suffix.hasPrefix("a") ? "am" : "pm"
      body = body.dropLast(suffix.count)
      break
    }
    let parts = body.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 1 || parts.count == 2, let hourPart = parts.first, (1...2).contains(hourPart.count),
      hourPart.allSatisfy(\.isASCIIDigit), var hour = Int(hourPart)
    else { return nil }
    var minute = 0
    if parts.count == 2 {
      guard parts[1].count == 2, parts[1].allSatisfy(\.isASCIIDigit), let m = Int(parts[1]), m < 60 else { return nil }
      minute = m
    }
    if let meridiem {
      guard (1...12).contains(hour) else { return nil }
      if meridiem == "am" && hour == 12 { hour = 0 }
      if meridiem == "pm" && hour != 12 { hour += 12 }
    } else {
      // Without am/pm only "H:MM" / "HH:MM" counts as a time (a bare number is not a time).
      guard parts.count == 2, hour < 24 else { return nil }
    }
    return TimeOfDay(hour: hour, minute: minute)
  }

  // MARK: Dates

  private func parseDatePart(_ t: [String], time: TimeOfDay?) -> Date? {
    let p = t.joined(separator: " ")
    switch p {
    case "now", "today", "tonight": return day(0)
    case "tomorrow", "tmr", "tmrw": return day(1)
    case "yesterday", "last night": return day(-1)
    case "the day after tomorrow", "day after tomorrow": return day(2)
    case "the day before yesterday", "day before yesterday": return day(-2)
    case "next week": return day(7)
    case "last week": return day(-7)
    case "next month": return addingMonths(1)
    case "last month": return addingMonths(-1)
    case "next year": return addingMonths(12)
    case "last year": return addingMonths(-12)
    case "weekend", "this weekend": return weekday(6, modifier: "this", time: time)
    case "next weekend": return weekday(6, modifier: "next", time: time)
    case "this morning", "this afternoon", "this evening", "this night":
      // "this evening 8pm" keeps the explicit time; either way only the day matters
      if time != nil { return day(0) }
      return timeOnly(parseTimePart([String(p.dropFirst(5))])!)
    default: break
    }

    if let date = parseWeekdayPhrase(t, time: time) { return date }
    if let date = parseRelative(t) { return date }
    if let date = parseAbsolute(t) { return date }
    return nil
  }

}

// MARK: - Weekdays (chrono-node's weekday calculation)

extension NaturalDateParser {

  private static let weekdays: [String: Int] = [
    "sunday": 0, "sun": 0,
    "monday": 1, "mon": 1,
    "tuesday": 2, "tue": 2, "tues": 2,
    "wednesday": 3, "wed": 3,
    "thursday": 4, "thu": 4, "thur": 4, "thurs": 4,
    "friday": 5, "fri": 5,
    "saturday": 6, "sat": 6,
  ]

  private static func weekdayNumber(_ token: String) -> Int? {
    weekdays[token.hasSuffix(".") ? String(token.dropLast()) : token]
  }

  private func parseWeekdayPhrase(_ t: [String], time: TimeOfDay?) -> Date? {
    switch t.count {
    case 1:
      guard let wd = Self.weekdayNumber(t[0]) else { return nil }
      return weekday(wd, modifier: nil, time: time)
    case 2:
      guard ["this", "next", "last", "coming", "on"].contains(t[0]), let wd = Self.weekdayNumber(t[1]) else {
        return nil
      }
      let modifier = t[0] == "coming" ? "this" : (t[0] == "on" ? nil : t[0])
      return weekday(wd, modifier: modifier, time: time)
    case 3:
      // "friday next week", "monday this week", "friday last week"
      guard let wd = Self.weekdayNumber(t[0]), t[2] == "week", ["this", "next", "last"].contains(t[1]) else {
        return nil
      }
      return weekday(wd, modifier: t[1], time: time)
    default:
      return nil
    }
  }

  private func weekday(_ target: Int, modifier: String?, time: TimeOfDay?) -> Date {
    let ref = refWeekday
    let forward = (target - ref + 7) % 7
    let backward = forward == 0 ? -7 : forward - 7
    var days: Int
    switch modifier {
    case "next":
      if ref == 0 {
        days = target == 0 ? 7 : target
      } else if ref == 6 {
        days = target == 6 ? 7 : (target == 0 ? 8 : 1 + target)
      } else if target < ref && target != 0 {
        days = forward
      } else {
        days = forward + 7
      }
    case "last":
      // chrono's "last <weekday>" pushed forward by forwardDate
      days = backward
      while days <= 0 { days += 7 }
    default:
      // bare / "this": the coming occurrence; today only if the (implied noon) time hasn't passed
      days = forward
      let minutes = time.map { $0.hour * 60 + $0.minute } ?? 12 * 60
      if days == 0 && minutes < nowMinutes { days = 7 }
    }
    return day(days)
  }

}

// MARK: - Relative durations

extension NaturalDateParser {

  private static let numberWords: [String: Int] = [
    "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
    "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "several": 7,
  ]

  private static func unit(_ token: String) -> DurationUnit? {
    switch token {
    case "second", "seconds", "sec", "secs": return .second
    case "minute", "minutes", "min", "mins": return .minute
    case "hour", "hours", "hr", "hrs", "h": return .hour
    case "day", "days", "d": return .day
    case "week", "weeks", "wk", "wks", "w": return .week
    case "month", "months", "mo", "mos": return .month
    case "year", "years", "yr", "yrs", "y": return .year
    default: return nil
    }
  }

  /// Parse "3 days", "a week", "5d", "a couple of days", "3 days 2 hours" (entire token list).
  private func parseDurations(_ tokens: [String]) -> [(Int, DurationUnit)]? {
    var t = tokens[...]
    var result: [(Int, DurationUnit)] = []
    while let first = t.first {
      var amount: Int?
      if first == "a" && t.dropFirst().first == "couple" {
        amount = 2
        t = t.dropFirst(2)
        if t.first == "of" { t = t.dropFirst() }
      } else if first == "a" && t.dropFirst().first == "few" {
        amount = 3
        t = t.dropFirst(2)
      } else if let n = Self.numberWords[first] {
        amount = n
        t = t.dropFirst()
      } else if first.allSatisfy(\.isASCIIDigit) {
        amount = Int(first)
        t = t.dropFirst()
      } else if let digitsEnd = first.firstIndex(where: { !$0.isASCIIDigit }), digitsEnd != first.startIndex,
        let unit = Self.unit(String(first[digitsEnd...])), let n = Int(first[..<digitsEnd])
      {
        // attached form: "5d", "2w", "3mo", "2mins"
        result.append((n, unit))
        t = t.dropFirst()
        continue
      }
      guard let amount, let unitToken = t.first, let unit = Self.unit(unitToken) else { return nil }
      result.append((amount, unit))
      t = t.dropFirst()
    }
    return result.isEmpty ? nil : result
  }

  private func parseRelative(_ t: [String]) -> Date? {
    guard let first = t.first, let last = t.last else { return nil }
    var body = t[...]
    var sign = 1
    if ["in", "within", "after"].contains(first) {
      body = body.dropFirst()
    } else if first == "next" {
      body = body.dropFirst()  // "next 2 weeks"
      guard let amount = body.first, amount.allSatisfy(\.isASCIIDigit) || Self.numberWords[amount] != nil else {
        return nil
      }
    } else if first.hasPrefix("+"), first.count > 1 {
      body = [String(first.dropFirst())] + body.dropFirst()
    } else if t.count >= 3 && t.suffix(2) == ["from", "now"] {
      body = body.dropLast(2)
    } else if last == "later" || last == "ago" {
      body = body.dropLast()
      if last == "ago" { sign = -1 }
    }
    guard !body.isEmpty, let durations = parseDurations(Array(body)) else { return nil }
    return applying(durations, sign: sign)
  }

  private func applying(_ durations: [(Int, DurationUnit)], sign: Int) -> Date? {
    var months = 0
    var days = 0
    var seconds = 0.0
    for (amount, unit) in durations {
      switch unit {
      case .year: months += 12 * amount
      case .month: months += amount
      case .week: days += 7 * amount
      case .day: days += amount
      case .hour: seconds += Double(amount) * 3600
      case .minute: seconds += Double(amount) * 60
      case .second: seconds += Double(amount)
      }
    }
    var date = now
    if months != 0 { date = addingMonths(sign * months, to: date) }
    if days != 0 { date = calendar.date(byAdding: .day, value: sign * days, to: date)! }
    return date.addingTimeInterval(Double(sign) * seconds)
  }

  /// JavaScript `setMonth(getMonth() + n)` semantics: day overflow rolls into the next month
  /// (Dec 30 + 2 months = Mar 2), unlike Foundation's clamping.
  private func addingMonths(_ n: Int, to base: Date? = nil) -> Date {
    let base = base ?? now
    var c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: base)
    let zeroBased = c.month! - 1 + n
    c.year! += zeroBased >= 0 ? zeroBased / 12 : (zeroBased - 11) / 12
    c.month = ((zeroBased % 12) + 12) % 12 + 1
    let requestedDay = c.day!
    c.day = 1
    let firstOfMonth = calendar.date(from: c)!
    return calendar.date(byAdding: .day, value: requestedDay - 1, to: firstOfMonth)!
  }

}

// MARK: - Absolute dates

extension NaturalDateParser {

  private static let months: [String: Int] = [
    "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4, "apr": 4, "may": 5,
    "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8, "september": 9, "sep": 9, "sept": 9,
    "october": 10, "oct": 10, "november": 11, "nov": 11, "december": 12, "dec": 12,
  ]

  private static func monthNumber(_ token: String) -> Int? {
    months[token.hasSuffix(".") ? String(token.dropLast()) : token]
  }

  /// "15", "15th", "1st", "22nd", "3rd"
  private static func dayNumber(_ token: String) -> Int? {
    var s = Substring(token)
    for suffix in ["st", "nd", "rd", "th"] where s.hasSuffix(suffix) {
      s = s.dropLast(2)
      break
    }
    guard (1...2).contains(s.count), s.allSatisfy(\.isASCIIDigit), let d = Int(s), (1...31).contains(d) else {
      return nil
    }
    return d
  }

  private static func yearNumber(_ token: String) -> Int? {
    guard token.count == 4, token.allSatisfy(\.isASCIIDigit) else { return nil }
    return Int(token)
  }

  private func parseAbsolute(_ tokens: [String]) -> Date? {
    var t = tokens
    // Optional leading weekday ("friday, october 30") — the explicit date wins
    if t.count >= 2, Self.weekdayNumber(t[0]) != nil { t.removeFirst() }
    if t.first == "the" { t.removeFirst() }
    guard !t.isEmpty else { return nil }

    var month: Int?
    var dayOfMonth: Int?
    var year: Int?
    switch t.count {
    case 1:
      if let m = Self.monthNumber(t[0]) {
        (month, dayOfMonth) = (m, 1)
      } else {
        return parseNumericDate(t[0])
      }
    case 2:
      if let m = Self.monthNumber(t[0]), let d = Self.dayNumber(t[1]) {
        (month, dayOfMonth) = (m, d)
      } else if let d = Self.dayNumber(t[0]), let m = Self.monthNumber(t[1]) {
        (month, dayOfMonth) = (m, d)
      } else if let m = Self.monthNumber(t[0]), let y = Self.yearNumber(t[1]) {
        (month, dayOfMonth, year) = (m, 1, y)
      } else {
        return nil
      }
    case 3:
      if let m = Self.monthNumber(t[0]), let d = Self.dayNumber(t[1]), let y = Self.yearNumber(t[2]) {
        (month, dayOfMonth, year) = (m, d, y)
      } else if let d = Self.dayNumber(t[0]), let m = Self.monthNumber(t[1]), let y = Self.yearNumber(t[2]) {
        (month, dayOfMonth, year) = (m, d, y)
      } else if let d = Self.dayNumber(t[0]), t[1] == "of", let m = Self.monthNumber(t[2]) {
        (month, dayOfMonth) = (m, d)
      } else {
        return nil
      }
    case 4:
      guard let d = Self.dayNumber(t[0]), t[1] == "of", let m = Self.monthNumber(t[2]), let y = Self.yearNumber(t[3])
      else { return nil }
      (month, dayOfMonth, year) = (m, d, y)
    default:
      return nil
    }
    return resolve(month: month!, day: dayOfMonth!, year: year)
  }

  /// "4/15", "25/12", "12/25/2027", "12/25/27", "11-05-2026", "2026/11/05", "2027-01-02T10:00[:00][Z|±hh:mm]"
  private func parseNumericDate(_ token: String) -> Date? {
    if let date = parseISODateTime(token) { return date }
    let separators: Set<Character> = ["/", "-", "."]
    guard let separator = token.first(where: { separators.contains($0) }) else { return nil }
    let parts = token.split(separator: separator, omittingEmptySubsequences: false)
    guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }) else { return nil }
    let numbers = parts.compactMap { Int($0) }

    if parts.count == 3 && parts[0].count == 4 {
      return resolve(month: numbers[1], day: numbers[2], year: numbers[0])  // Y/M/D
    }
    guard parts.count == 2 || parts.count == 3, parts[0].count <= 2, parts[1].count <= 2 else { return nil }
    var (month, dayOfMonth) = (numbers[0], numbers[1])
    if month > 12 && dayOfMonth <= 12 { (month, dayOfMonth) = (dayOfMonth, month) }  // D/M when unambiguous
    var year: Int?
    if parts.count == 3 {
      switch parts[2].count {
      case 4: year = numbers[2]
      case 2: year = numbers[2] < 50 ? 2000 + numbers[2] : 1900 + numbers[2]
      default: return nil
      }
    }
    return resolve(month: month, day: dayOfMonth, year: year)
  }

  private func parseISODateTime(_ token: String) -> Date? {
    guard token.count > 10, let tIndex = token.firstIndex(where: { $0 == "t" }),
      isISODateString(String(token[..<tIndex]))
    else { return nil }
    let datePart = token[..<tIndex].split(separator: "-").compactMap { Int($0) }
    var rest = token[token.index(after: tIndex)...]
    var offsetSeconds: Int?
    if rest.hasSuffix("z") {
      offsetSeconds = 0
      rest = rest.dropLast()
    } else if let signIndex = rest.lastIndex(where: { $0 == "+" || $0 == "-" }) {
      let offset = rest[rest.index(after: signIndex)...].filter { $0 != ":" }
      guard offset.count == 4, offset.allSatisfy(\.isASCIIDigit), let hhmm = Int(offset) else { return nil }
      offsetSeconds = (hhmm / 100 * 3600 + hhmm % 100 * 60) * (rest[signIndex] == "-" ? -1 : 1)
      rest = rest[..<signIndex]
    }
    let timeParts = rest.split(separator: ":", omittingEmptySubsequences: false)
    guard (2...3).contains(timeParts.count), timeParts[0].count == 2, timeParts[1].count == 2,
      let hour = Int(timeParts[0]), let minute = Int(timeParts[1]), hour < 24, minute < 60
    else { return nil }
    var second = 0.0
    if timeParts.count == 3 {
      guard let s = Double(timeParts[2]), timeParts[2].first?.isASCIIDigit == true, s < 61 else { return nil }
      second = s
    }
    var c = DateComponents(year: datePart[0], month: datePart[1], day: datePart[2], hour: hour, minute: minute)
    guard isValid(year: datePart[0], month: datePart[1], day: datePart[2]) else { return nil }
    if let offsetSeconds {
      var utc = Calendar(identifier: .gregorian)
      utc.timeZone = TimeZone(secondsFromGMT: 0)!
      c.timeZone = utc.timeZone
      guard let instant = utc.date(from: c) else { return nil }
      return instant.addingTimeInterval(second - Double(offsetSeconds))
    }
    return calendar.date(from: c)?.addingTimeInterval(second)
  }

  private func isValid(year: Int, month: Int, day: Int) -> Bool {
    guard (1...12).contains(month), day >= 1 else { return false }
    guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
      let range = calendar.range(of: .day, in: .month, for: first)
    else { return false }
    return range.contains(day)
  }

  /// Month/day with optional year. Without a year, the next occurrence (forwardDate, implied noon).
  private func resolve(month: Int, day dayOfMonth: Int, year: Int?) -> Date? {
    if let year {
      guard isValid(year: year, month: month, day: dayOfMonth) else { return nil }
      return calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))
    }
    let currentYear = calendar.component(.year, from: now)
    guard isValid(year: currentYear, month: month, day: dayOfMonth),
      let candidate = calendar.date(from: DateComponents(year: currentYear, month: month, day: dayOfMonth))
    else { return nil }
    // chrono implies noon for a date without a time; forwardDate moves it to next year once that has passed
    if candidate.addingTimeInterval(12 * 3600) >= now { return candidate }
    guard isValid(year: currentYear + 1, month: month, day: dayOfMonth) else { return nil }
    return calendar.date(from: DateComponents(year: currentYear + 1, month: month, day: dayOfMonth))
  }
}

extension Character {
  fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}
