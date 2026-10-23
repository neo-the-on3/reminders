import Foundation

/// "Now" and the user's time zone: everything that decides which day is today. Injected so tests are deterministic.
public struct DayClock: Sendable {
  public var now: Date
  public var calendar: Calendar

  public init(now: Date = .now, timeZone: TimeZone = .current) {
    self.now = now
    self.calendar = .gregorian(in: timeZone)
  }

  public var timeZone: TimeZone { calendar.timeZone }

  public var today: CalendarDay { CalendarDay(now, in: calendar) }

  /// Whole days from today to `day` (negative when it is in the past).
  public func days(until day: CalendarDay) -> Int {
    guard let start = calendar.date(from: today.dateComponents), let end = day.startDate(in: calendar) else { return 0 }
    return calendar.dateComponents([.day], from: start, to: end).day ?? 0
  }
}
