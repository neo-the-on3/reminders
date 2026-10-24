import Foundation

/// Renders values as the human-readable (non-`--json`) output.
public struct TextRenderer: Sendable {
  public var style: TerminalStyle
  /// Show notes previews instead of a bare 📝 badge.
  public var verbose: Bool
  /// Decides what "today", "tomorrow" and "3d overdue" mean.
  public var clock: DayClock

  public init(style: TerminalStyle = .plain, verbose: Bool = false, clock: DayClock = DayClock()) {
    self.style = style
    self.verbose = verbose
    self.clock = clock
  }

  /// A horizontal rule `width` columns wide.
  func rule(_ width: Int) -> String { String(repeating: "─", count: width) }

  // MARK: Errors and messages

  func error(_ error: RemindersError) -> String {
    var text = style("Error: \(error.message)\n", .red)
    if let suggestion = error.suggestion { text += style("Suggestion: \(suggestion)\n", .yellow) }
    return text
  }

  func confirmation(_ message: String) -> String {
    "\(style("✓", .green)) \(message)\n"
  }

  // MARK: Lists

  func lists(_ lists: [ReminderList]) -> String {
    guard !lists.isEmpty else { return "No reminder lists found.\n" }
    let nameWidth = max(lists.map(\.title.terminalWidth).max() ?? 0, 4)
    var text = "\(style("Name".padded(to: nameWidth), .bold))  \(style("Count", .bold))  \(style("Overdue", .bold))\n"
    text += rule(nameWidth + 16) + "\n"
    for list in lists {
      let count = String(list.reminderCount).padded(to: 5, leading: true)
      let overdue = String(list.overdueCount).padded(to: 7, leading: true)
      text += "\(list.title.padded(to: nameWidth))  \(count)  \(style(overdue, list.overdueCount > 0 ? .red : .dim))\n"
    }
    return text
  }

  // MARK: Reminders

  func reminders(_ reminders: [Reminder], heading: String?, layout: ReminderLayout) -> String {
    guard !reminders.isEmpty else {
      return "No reminders found\(heading.map { " in \"\($0)\"" } ?? "").\n"
    }
    var text = ""
    if let heading {
      let overdue = reminders.count(where: clock.isOverdue)
      var summary = ["\(reminders.count) reminder\(reminders.count == 1 ? "" : "s")"]
      // Everything under "Overdue" is overdue, so the count would only repeat the total.
      if overdue > 0 && layout.context != .overdue { summary.append(style("\(overdue) overdue", .red)) }
      text += style("\n\(heading)", .bold) + style(" (\(summary.joined(separator: ", ")))\n", .dim)
      text += rule(heading.terminalWidth + 2) + "\n"
    }

    let sectionNames = layout.groupBySection ? reminders.compactMap(\.sectionName).uniqued() : []
    if sectionNames.isEmpty {
      for reminder in reminders { text += line(for: reminder, layout: layout, showSection: true) }
    } else {
      for section in sectionNames {
        text += "\n \(style(section, .bold, .underline))\n"
        for reminder in reminders where reminder.sectionName == section {
          text += line(for: reminder, layout: layout, showSection: false)
        }
      }
      let unsectioned = reminders.filter { $0.sectionName == nil }
      if !unsectioned.isEmpty {
        text += "\n \(style("Others", .dim, .underline))\n"
        for reminder in unsectioned { text += line(for: reminder, layout: layout, showSection: true) }
      }
    }
    return text + "\n"
  }

  func line(for reminder: Reminder, layout: ReminderLayout, showSection: Bool) -> String {
    let checkbox = reminder.isCompleted ? style("✓", .green) : style("○", .dim)
    let title = reminder.isCompleted ? style(style(reminder.title, .dim), .strikethrough) : reminder.title
    var badges: [String] = []

    if let due = reminder.dueDate, layout.showsDueDate {
      badges.append(dueBadge(due, emphasizeOverdue: layout.context == .overdue))
    }
    if let recurrence = reminder.recurrence {
      badges.append(style("↻ \(recurrence)", .blue))
    } else if reminder.isRecurring {
      badges.append(style("↻", .blue))
    }
    switch reminder.priority {
    case .high: badges.append(style("!!!", .red))
    case .medium: badges.append(style("!!", .yellow))
    case .low: badges.append(style("!", .blue))
    case .none: break
    }
    if reminder.isFlagged == true { badges.append(style("⚑", .orange)) }
    if let notes = reminder.notes, !notes.isEmpty {
      if verbose {
        let preview = notes.count > 60 ? "\(notes.prefix(57))..." : notes
        badges.append(style("📝 \(preview)", .dim))
      } else {
        badges.append(style("📝", .dim))
      }
    }
    if showSection, let section = reminder.sectionName { badges.append(style("[\(section)]", .cyan)) }
    if layout.showsList && !reminder.listName.isEmpty { badges.append(style("[\(reminder.listName)]", .magenta)) }

    let suffix = badges.isEmpty ? "" : " " + badges.joined(separator: "  ")
    return " \(checkbox) \(title)\(suffix)\n"
  }

  private func dueBadge(_ day: CalendarDay, emphasizeOverdue: Bool) -> String {
    let (text, attribute) = relativeDescription(of: day)
    return style(text, emphasizeOverdue ? .red : attribute)
  }

  private static let monthAbbreviations = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ]

  /// "3d overdue", "today", "tomorrow", "in 5d", "Nov 15" or "Apr 1 2027", and how to colour it.
  func relativeDescription(of day: CalendarDay) -> (String, TextAttribute) {
    let days = clock.days(until: day)
    switch days {
    case ..<0: return ("\(-days)d overdue", .red)
    case 0: return ("today", .yellow)
    case 1: return ("tomorrow", .dim)
    case 2...7: return ("in \(days)d", .dim)
    default:
      let date = "\(Self.monthAbbreviations[day.month - 1]) \(day.day)"
      return (day.year == clock.today.year ? date : "\(date) \(day.year)", .dim)
    }
  }

  // MARK: Sections

  func sections(_ sections: [Section], listName: String, counts: [String: Int]?) -> String {
    guard !sections.isEmpty else { return "No sections found in \"\(listName)\".\n" }
    var text = style("\nSections in \"\(listName)\"\n", .bold) + rule(listName.terminalWidth + 14) + "\n"
    for section in sections {
      let count = counts?[section.displayName].map { style(" (\($0))", .dim) } ?? ""
      text += " • \(section.displayName)\(count)\n"
    }
    return text + "\n"
  }
}

/// Which view a reminder listing belongs to, and what it therefore shows.
public struct ReminderLayout: Sendable, Hashable {
  public enum Context: Sendable, Hashable {
    case list, today, overdue, upcoming, search
  }

  public var context: Context
  /// Cross-list views tag each reminder with its list.
  public var showsList: Bool
  /// Order by due date, earliest first and undated last. ``ReminderListing`` applies it, so text and JSON agree.
  public var sortByDueDate: Bool
  /// Group under section headings (when any reminder has a section).
  public var groupBySection: Bool

  public init(_ context: Context, showsList: Bool = false, sortByDueDate: Bool = true, groupBySection: Bool = false) {
    self.context = context
    self.showsList = showsList
    self.sortByDueDate = sortByDueDate
    self.groupBySection = groupBySection
  }

  /// "Due today" already says when everything is due.
  var showsDueDate: Bool { context != .today }

  public static let list = ReminderLayout(.list, groupBySection: true)
  public static let today = ReminderLayout(.today, showsList: true)
  public static let overdue = ReminderLayout(.overdue, showsList: true)
  public static let upcoming = ReminderLayout(.upcoming, showsList: true)
  public static let search = ReminderLayout(.search, showsList: true)
}

extension Reminder {
  fileprivate var sectionName: String? { section?.isEmpty == false ? section : nil }
}

extension [Reminder] {
  /// Earliest due date first, undated last; ties keep their order.
  func sortedByDueDate() -> [Reminder] {
    enumerated().sorted { lhs, rhs in
      switch (lhs.element.dueDate, rhs.element.dueDate) {
      case (let left?, let right?) where left != right: left < right
      case (nil, _?): false
      case (_?, nil): true
      default: lhs.offset < rhs.offset
      }
    }.map(\.element)
  }

  /// Grouped by section in `order`, keeping each group's order: sections not in `order` next, then reminders in
  /// no section.
  func grouped(bySectionOrder order: [String]) -> [Reminder] {
    let positions = Dictionary(
      order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
    func rank(of reminder: Reminder) -> Int {
      guard let name = reminder.sectionName else { return order.count + 1 }
      return positions[name] ?? order.count
    }
    return enumerated().sorted { lhs, rhs in
      let (left, right) = (rank(of: lhs.element), rank(of: rhs.element))
      return left != right ? left < right : lhs.offset < rhs.offset
    }.map(\.element)
  }
}

extension Sequence where Element: Hashable {
  fileprivate func uniqued() -> [Element] {
    var seen: Set<Element> = []
    return filter { seen.insert($0).inserted }
  }
}

extension String {
  /// Columns the string occupies in a terminal: emoji and East Asian wide characters take two.
  var terminalWidth: Int {
    reduce(0) { width, character in
      guard let scalar = character.unicodeScalars.first else { return width }
      let properties = scalar.properties
      let isWide =
        properties.isEmojiPresentation || character.unicodeScalars.contains { $0.value == 0xFE0F }
        || (0x1100...0x115F).contains(scalar.value) || (0x2E80...0xA4CF).contains(scalar.value)
        || (0xAC00...0xD7A3).contains(scalar.value) || (0xF900...0xFAFF).contains(scalar.value)
        || (0xFE30...0xFE4F).contains(scalar.value) || (0xFF00...0xFF60).contains(scalar.value)
        || (0xFFE0...0xFFE6).contains(scalar.value)
      return width + (isWide ? 2 : 1)
    }
  }

  /// Padded with spaces to `width` terminal columns (on the left when `leading`).
  func padded(to width: Int, leading: Bool = false) -> String {
    let padding = String(repeating: " ", count: max(0, width - terminalWidth))
    return leading ? padding + self : self + padding
  }
}
