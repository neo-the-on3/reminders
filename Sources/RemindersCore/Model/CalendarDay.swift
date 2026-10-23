import Foundation

/// A day in the Gregorian calendar with no time or zone, such as a reminder's due date. Written `YYYY-MM-DD`.
public struct CalendarDay: Hashable, Sendable, Comparable {
  public let year: Int
  public let month: Int
  public let day: Int

  /// A valid day, or nil for impossible dates such as February 30.
  public init?(year: Int, month: Int, day: Int) {
    guard (1...12).contains(month), (1...Self.numberOfDays(year: year, month: month)).contains(day) else {
      return nil
    }
    self.year = year
    self.month = month
    self.day = day
  }

  /// The day containing `date` in `calendar`'s time zone.
  public init(_ date: Date, in calendar: Calendar) {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    year = parts.year ?? 1
    month = parts.month ?? 1
    day = parts.day ?? 1
  }

  /// Midnight at the start of this day in `calendar`'s time zone.
  public func startDate(in calendar: Calendar) -> Date? {
    calendar.date(from: dateComponents)
  }

  /// Year, month and day components (what EventKit stores as a reminder's due date).
  public var dateComponents: DateComponents {
    DateComponents(year: year, month: month, day: day)
  }

  /// This day moved by `days` (negative goes back).
  public func adding(days: Int) -> CalendarDay {
    let calendar = Calendar.gregorianUTC
    let date = calendar.date(byAdding: .day, value: days, to: startDate(in: calendar)!)!
    return CalendarDay(date, in: calendar)
  }

  public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }

  static func numberOfDays(year: Int, month: Int) -> Int {
    switch month {
    case 2: (year.isMultiple(of: 4) && !year.isMultiple(of: 100)) || year.isMultiple(of: 400) ? 29 : 28
    case 4, 6, 9, 11: 30
    default: 31
    }
  }
}

extension CalendarDay: LosslessStringConvertible {
  /// Parses exactly `YYYY-MM-DD`.
  public init?(_ description: String) {
    let parts = description.split(separator: "-", omittingEmptySubsequences: false)
    guard description.utf8.count == 10, parts.count == 3, parts[0].count == 4, parts[1].count == 2,
      parts[2].count == 2, parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
    else { return nil }
    self.init(year: year, month: month, day: day)
  }

  public var description: String {
    let yearText = String(year)
    let padded = String(repeating: "0", count: max(0, 4 - yearText.count)) + yearText
    return padded + "-" + (month < 10 ? "0" : "") + String(month) + "-" + (day < 10 ? "0" : "") + String(day)
  }
}

extension CalendarDay: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let day = CalendarDay(text) else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected YYYY-MM-DD, got \(text)")
    }
    self = day
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }
}

extension Calendar {
  /// The Gregorian calendar in `timeZone` (date logic never depends on the user's calendar preference).
  public static func gregorian(in timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }

  static let gregorianUTC = gregorian(in: TimeZone(identifier: "UTC")!)
}

extension Character {
  var isASCIIDigit: Bool { isASCII && isWholeNumber }
}
