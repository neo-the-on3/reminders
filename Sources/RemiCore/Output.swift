// Ported from remi src/cli/output.ts (MIT, Matthew O'Riordan).
//
// All user-facing output goes through ``Output`` so CLI commands and tests share one implementation.
// In JSON mode every result is wrapped as `{ "success": true, "data": … }` on stdout, and errors as
// `{ "success": false, "error": { code, message, suggestion? } }` on stderr, pretty-printed with two
// spaces exactly like `JSON.stringify(result, null, 2)`.

import Foundation

/// Destination for output text.
public protocol TextSink: AnyObject {
  func write(_ text: String)
}

/// Writes to a `FileHandle` (stdout/stderr) without buffering.
public final class FileHandleSink: TextSink {
  private let handle: FileHandle
  public init(_ handle: FileHandle) { self.handle = handle }
  public func write(_ text: String) { handle.write(Data(text.utf8)) }
}

/// Collects output in memory (for tests and for the MCP server).
public final class StringSink: TextSink {
  public private(set) var text = ""
  public init() {}
  public func write(_ text: String) { self.text += text }
}

/// View context: suppresses redundant information.
public enum ReminderViewContext: String, Sendable {
  case today, overdue, upcoming, search, list
}

/// Options for reminder display.
public struct OutputRemindersOptions: Sendable {
  public var context: ReminderViewContext?
  /// Show which list each reminder belongs to (cross-list views).
  public var showList: Bool
  /// Sort by due date.
  public var sortByDate: Bool
  /// Group reminders by section (shows section headers).
  public var groupBySections: Bool

  public init(
    context: ReminderViewContext? = nil, showList: Bool = false, sortByDate: Bool = false,
    groupBySections: Bool = false
  ) {
    self.context = context
    self.showList = showList
    self.sortByDate = sortByDate
    self.groupBySections = groupBySections
  }
}

/// Human and JSON output for remi.
public final class Output {
  public var jsonMode: Bool
  public var verboseMode: Bool
  public var style: Styler
  public let stdout: TextSink
  public let stderr: TextSink
  /// Reference clock and zone for relative dates ("today", "3d overdue").
  public var now: () -> Date
  public var timeZone: TimeZone

  public init(
    jsonMode: Bool = false, verboseMode: Bool = false, style: Styler = .plain, stdout: TextSink, stderr: TextSink,
    now: @escaping () -> Date = Date.init, timeZone: TimeZone = .current
  ) {
    self.jsonMode = jsonMode
    self.verboseMode = verboseMode
    self.style = style
    self.stdout = stdout
    self.stderr = stderr
    self.now = now
    self.timeZone = timeZone
  }

  /// Output bound to the process's stdout/stderr, with colour detected like chalk.
  public static func standard() -> Output {
    let isTTY = isatty(STDOUT_FILENO) != 0
    let level = ColorLevel.detect(isTTY: isTTY, environment: ProcessInfo.processInfo.environment)
    return Output(
      style: Styler(level: level), stdout: FileHandleSink(.standardOutput), stderr: FileHandleSink(.standardError))
  }

  // MARK: - Date formatting

  struct RelativeDate: Equatable {
    var text: String
    var isOverdue: Bool
    var isToday: Bool
  }

  private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

  func formatRelativeDate(_ dateString: String) -> RelativeDate {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let current = now()
    let today = calendar.startOfDay(for: current)
    // new Date(`${dateStr}T00:00:00`): local midnight of the given day
    let parts = dateString.prefix(10).split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3,
      let due = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    else {
      // JavaScript would render "Invalid Date" (NaN); keep the raw text and don't flag it
      return RelativeDate(text: dateString, isOverdue: false, isToday: false)
    }
    let diffDays = Int((due.timeIntervalSince(today) / 86_400).rounded(.toNearestOrAwayFromZero))

    if diffDays < 0 {
      let absDays = abs(diffDays)
      return RelativeDate(text: absDays == 1 ? "1d overdue" : "\(absDays)d overdue", isOverdue: true, isToday: false)
    }
    if diffDays == 0 { return RelativeDate(text: "today", isOverdue: false, isToday: true) }
    if diffDays == 1 { return RelativeDate(text: "tomorrow", isOverdue: false, isToday: false) }
    if diffDays <= 7 { return RelativeDate(text: "in \(diffDays)d", isOverdue: false, isToday: false) }

    let c = calendar.dateComponents([.year, .month, .day], from: due)
    let month = Self.monthNames[c.month! - 1]
    if c.year == calendar.component(.year, from: current) {
      return RelativeDate(text: "\(month) \(c.day!)", isOverdue: false, isToday: false)
    }
    return RelativeDate(text: "\(month) \(c.day!) \(c.year!)", isOverdue: false, isToday: false)
  }

  private func colorDate(_ dateString: String, context: ReminderViewContext?) -> String {
    // Skip redundant date display in context-specific views
    if context == .today { return "" }
    let relative = formatRelativeDate(dateString)
    if context == .overdue { return style(relative.text, .red) }
    if relative.isOverdue { return style(relative.text, .red) }
    if relative.isToday { return style(relative.text, .yellow) }
    return style(relative.text, .dim)
  }

  // MARK: - Core output

  /// Output a successful result.
  public func success(_ data: some JSONValueConvertible) {
    if jsonMode {
      let result: JSONValue = .object([("success", .bool(true)), ("data", data.jsonValue)])
      stdout.write(result.stringified(indent: 2) + "\n")
    } else {
      stdout.write(data.jsonValue.stringified(indent: 2) + "\n")
    }
  }

  /// Output an error result.
  public func error(_ error: RemiError) {
    if jsonMode {
      let result: JSONValue = .object([("success", .bool(false)), ("error", error.jsonValue)])
      stderr.write(result.stringified(indent: 2) + "\n")
    } else {
      stderr.write(style("Error: \(error.message)\n", .red))
      if let suggestion = error.suggestion {
        stderr.write(style("Suggestion: \(suggestion)\n", .yellow))
      }
    }
  }

  /// Output a simple success message, with extra fields merged into the JSON data.
  public func message(_ message: String, data: [(String, JSONValue)] = []) {
    if jsonMode {
      // { message, ...data }: later keys override earlier ones but keep their position
      var object: JSONValue = .object([("message", .string(message))])
      for (key, value) in data { object[key] = value }
      success(object)
      return
    }
    stdout.write("\(style("✓", .green)) \(message)\n")
  }

  // MARK: - Lists

  /// Format and output reminder lists.
  public func lists(_ lists: [ReminderList]) {
    if jsonMode {
      success(lists)
      return
    }
    if lists.isEmpty {
      stdout.write("No reminder lists found.\n")
      return
    }
    let maxNameLength = max(lists.map(\.title.jsLength).max() ?? 0, 4)
    stdout.write(
      "\(style("Name".jsPadEnd(maxNameLength), .bold))  \(style("Count", .bold))  \(style("Overdue", .bold))\n")
    stdout.write(String(repeating: "─", count: maxNameLength + 16) + "\n")
    for list in lists {
      let count = String(list.reminderCount).jsPadStart(5)
      let overdue =
        list.overdueCount > 0
        ? style(String(list.overdueCount).jsPadStart(7), .red) : style("0".jsPadStart(7), .dim)
      stdout.write("\(list.title.jsPadEnd(maxNameLength))  \(count)  \(overdue)\n")
    }
  }

  // MARK: - Reminders

  /// Format and output reminders.
  public func reminders(_ reminders: [Reminder], listName: String? = nil, options: OutputRemindersOptions = .init()) {
    if jsonMode {
      success(reminders)
      return
    }
    if reminders.isEmpty {
      let context = listName.map { " in \"\($0)\"" } ?? ""
      stdout.write("No reminders found\(context).\n")
      return
    }

    var sorted = reminders
    if options.sortByDate {
      // Stable sort: undated last, otherwise by YYYY-MM-DD string
      sorted = reminders.enumerated().sorted { a, b in
        switch (a.element.dueDate, b.element.dueDate) {
        case (nil, nil): return a.offset < b.offset
        case (nil, _): return false
        case (_, nil): return true
        case (let x?, let y?): return x == y ? a.offset < b.offset : x < y
        }
      }.map(\.element)
    }

    if let listName {
      let overdueCount = sorted.filter { r in r.dueDate.map { formatRelativeDate($0).isOverdue } ?? false }.count
      var summary = ["\(sorted.count) reminder\(sorted.count == 1 ? "" : "s")"]
      if overdueCount > 0 { summary.append(style("\(overdueCount) overdue", .red)) }
      stdout.write(style("\n\(listName)", .bold) + style(" (\(summary.joined(separator: ", ")))\n", .dim))
      stdout.write(String(repeating: "─", count: listName.jsLength + 2) + "\n")
    }

    if options.groupBySections && sorted.contains(where: { $0.section?.isEmpty == false }) {
      // Unique sections in order of first appearance
      var sectionOrder: [String] = []
      for r in sorted {
        if let section = r.section, !section.isEmpty, !sectionOrder.contains(section) { sectionOrder.append(section) }
      }
      for section in sectionOrder {
        stdout.write("\n \(style(section, .bold, .underline))\n")
        for r in sorted where r.section == section {
          stdout.write(formatReminderLine(r, options: options, hideSection: true))
        }
      }
      let unsectioned = sorted.filter { $0.section?.isEmpty ?? true }
      if !unsectioned.isEmpty {
        if !sectionOrder.isEmpty { stdout.write("\n \(style("Others", .dim, .underline))\n") }
        for r in unsectioned { stdout.write(formatReminderLine(r, options: options, hideSection: false)) }
      }
    } else {
      for r in sorted { stdout.write(formatReminderLine(r, options: options, hideSection: false)) }
    }
    stdout.write("\n")
  }

  func formatReminderLine(_ r: Reminder, options: OutputRemindersOptions, hideSection: Bool) -> String {
    let checkbox = r.isCompleted ? style("✓", .green) : style("○", .dim)
    let title = r.isCompleted ? style(style(r.title, .dim), .strikethrough) : r.title

    var line = " \(checkbox) \(title)"
    var badges: [String] = []

    if let dueDate = r.dueDate, !dueDate.isEmpty {
      let date = colorDate(dueDate, context: options.context)
      if !date.isEmpty { badges.append(date) }
    }

    if let recurrence = r.recurrence, !recurrence.isEmpty {
      badges.append(style("↻ \(recurrence)", .blue))
    } else if r.isRecurring == true {
      badges.append(style("↻", .blue))
    }

    switch r.priority {
    case .high: badges.append(style("!!!", .red))
    case .medium: badges.append(style("!!", .yellow))
    case .low: badges.append(style("!", .blue))
    case .none: break
    }

    if r.flagged == true { badges.append(style("⚑", .orange)) }

    if let notes = r.notes, !notes.isEmpty {
      if verboseMode {
        let preview = notes.jsLength > 60 ? "\(notes.jsPrefix(57))..." : notes
        badges.append(style("📝 \(preview)", .dim))
      } else {
        badges.append(style("📝", .dim))
      }
    }

    if let section = r.section, !section.isEmpty, !hideSection {
      badges.append(style("[\(section)]", .cyan))
    }

    if options.showList && !r.listName.isEmpty {
      badges.append(style("[\(r.listName)]", .magenta))
    }

    if !badges.isEmpty { line += " " + badges.joined(separator: "  ") }
    return line + "\n"
  }

  // MARK: - Sections

  /// Format and output sections with optional reminder counts (keyed by section display name).
  public func sections(_ sections: [Section], listName: String, counts: [String: Int]? = nil) {
    if jsonMode {
      success(sections)
      return
    }
    if sections.isEmpty {
      stdout.write("No sections found in \"\(listName)\".\n")
      return
    }
    stdout.write(style("\nSections in \"\(listName)\"\n", .bold))
    stdout.write(String(repeating: "─", count: listName.jsLength + 14) + "\n")
    for s in sections {
      let countText = counts?[s.displayName].map { style(" (\($0))", .dim) } ?? ""
      stdout.write(" • \(s.displayName)\(countText)\n")
    }
    stdout.write("\n")
  }
}
