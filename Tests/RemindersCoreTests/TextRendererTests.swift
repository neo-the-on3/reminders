import Foundation
import Testing

@testable import RemindersCore

struct RenderingCase: Sendable, CustomTestStringConvertible {
  let name: String
  let verbose: Bool
  let color: Bool
  let stdout: String
  let stderr: String

  init(_ name: String, verbose: Bool, color: Bool, stdout: String, stderr: String) {
    self.name = name
    self.verbose = verbose
    self.color = color
    self.stdout = stdout
    self.stderr = stderr
  }

  var testDescription: String { "\(name) verbose=\(verbose) color=\(color)" }
}

let referenceInstant = ISO8601DateFormatter().date(from: "2026-10-23T10:00:00Z")!
let utcClock = DayClock(now: referenceInstant, timeZone: TimeZone(identifier: "UTC")!)

func makeConsole(json: Bool = false, verbose: Bool = false, color: Bool = false) -> (Console, TextBuffer, TextBuffer) {
  let output = TextBuffer()
  let errors = TextBuffer()
  let renderer = TextRenderer(style: TerminalStyle(color ? .trueColor : .none), verbose: verbose, clock: utcClock)
  return (Console(format: json ? .json : .text, renderer: renderer, output: output, errors: errors), output, errors)
}

private func day(_ text: String) -> CalendarDay { CalendarDay(text)! }

let sampleReminders: [Reminder] = [
  Reminder(
    id: "A1", title: "Buy milk", listID: "L1", listName: "Groceries", priority: .high, dueDate: day("2026-10-23"),
    notes: "Organic only, the big bottle from the shop round the corner please", section: "Dairy", isFlagged: true),
  Reminder(
    id: "A2", title: "Pay rent", listID: "L2", listName: "Home", priority: .medium, dueDate: day("2026-10-20"),
    recurrence: Recurrence(.monthly)),
  Reminder(
    id: "A3", title: "Call mum", isCompleted: true, listID: "L2", listName: "Home", dueDate: day("2026-10-22"),
    completionDate: ISO8601DateFormatter().date(from: "2026-10-22T08:30:00Z")),
  Reminder(
    id: "A4", title: "Dentist", listID: "L2", listName: "Home", priority: .low, dueDate: day("2026-10-24"),
    isRecurring: true),
  Reminder(id: "A5", title: "Renew passport", listID: "L2", listName: "Home", dueDate: day("2026-11-15")),
  Reminder(
    id: "A6", title: "File taxes", listID: "L3", listName: "Admin", dueDate: day("2027-04-01"), section: "Money"),
  Reminder(id: "A7", title: "Read book", listID: "L3", listName: "Admin", notes: "Short note"),
  Reminder(id: "A8", title: "Soon", listID: "L3", listName: "Admin", dueDate: day("2026-10-28"), section: "Dairy"),
]

private let sampleLists = [
  ReminderList(id: "L1", title: "Groceries", reminderCount: 12, overdueCount: 0),
  ReminderList(id: "L2", title: "Home 🏠", reminderCount: 3, overdueCount: 2),
  ReminderList(id: "L3", title: "Ad", reminderCount: 0, overdueCount: 0),
]

private let sampleSections = [
  Section(id: "S1", displayName: "Dairy", listName: "Groceries", sortOrder: 0),
  Section(id: "S2", displayName: "Produce", listName: "Groceries", sortOrder: 1),
]

private func render(_ name: String, on console: Console) {
  let unsorted = ReminderLayout(.list, sortByDueDate: false)
  switch name {
  case "lists": console.show(ListOverview(sampleLists))
  case "listsEmpty": console.show(ListOverview([]))
  case "remindersPlain": console.show(ReminderListing(sampleReminders, heading: nil, layout: unsorted))
  case "remindersEmpty": console.show(ReminderListing([], heading: "Groceries", layout: .list))
  case "remindersList":
    console.show(
      ReminderListing(
        sampleReminders, heading: "Groceries", layout: ReminderLayout(.list, sortByDueDate: false, groupBySection: true)
      ))
  case "remindersToday": console.show(ReminderListing(sampleReminders, heading: nil, layout: .today))
  case "remindersOverdue":
    console.show(
      ReminderListing(
        sampleReminders, heading: nil, layout: ReminderLayout(.overdue, showsList: true, sortByDueDate: false)))
  case "remindersSorted": console.show(ReminderListing(sampleReminders, heading: "All", layout: ReminderLayout(.list)))
  case "sections": console.show(SectionListing(sampleSections, listName: "Groceries", counts: ["Dairy": 3]))
  case "sectionsEmpty": console.show(SectionListing([], listName: "Groceries"))
  case "message": console.show(Confirmation("Created reminder"))
  case "error":
    console.report(
      RemindersError(.listNotFound, "No list matching \"x\"", suggestion: "Available lists:\n  - A\n  - B"))
  default: Issue.record("unknown case \(name)")
  }
}

@Suite("Text output")
struct TextRendererTests {
  @Test("matches the reference output byte for byte", arguments: renderingCases)
  func reference(_ testCase: RenderingCase) {
    let (console, output, errors) = makeConsole(verbose: testCase.verbose, color: testCase.color)
    render(testCase.name, on: console)
    #expect(output.text == testCase.stdout)
    #expect(errors.text == testCase.stderr)
  }

  @Test("errors go to stderr with their suggestion; confirmations get a check mark")
  func messages() {
    let (console, output, errors) = makeConsole()
    console.report(RemindersError(.unknown, "Oops", suggestion: "Try again"))
    console.show(Confirmation("Done!"))
    #expect(errors.text == "Error: Oops\nSuggestion: Try again\n")
    #expect(output.text == "✓ Done!\n")
  }

  @Test("relative due dates")
  func relativeDates() {
    let renderer = TextRenderer(clock: utcClock)
    #expect(renderer.relativeDescription(of: day("2026-10-22")).0 == "1d overdue")
    #expect(renderer.relativeDescription(of: day("2026-10-13")).0 == "10d overdue")
    #expect(renderer.relativeDescription(of: day("2026-10-23")).0 == "today")
    #expect(renderer.relativeDescription(of: day("2026-10-24")).0 == "tomorrow")
    #expect(renderer.relativeDescription(of: day("2026-10-30")).0 == "in 7d")
    #expect(renderer.relativeDescription(of: day("2026-10-31")).0 == "Oct 31")
    #expect(renderer.relativeDescription(of: day("2027-01-02")).0 == "Jan 2 2027")
  }

  @Test("columns are measured in terminal cells (emoji and CJK are two wide)")
  func terminalWidth() {
    #expect("Home".terminalWidth == 4)
    #expect("Home 🏠".terminalWidth == 7)
    #expect("買い物".terminalWidth == 6)
    #expect("Cafe\u{301}".terminalWidth == 4)
    #expect("👨‍👩‍👧".terminalWidth == 2)
  }
}

@Suite("Terminal styling")
struct TerminalStyleTests {
  @Test("wraps text in ANSI sequences, re-opening around newlines and nested closes")
  func escapes() {
    let style = TerminalStyle(.basic)
    #expect(style("x", .red) == "\u{1B}[31mx\u{1B}[39m")
    #expect(style("x", .bold, .underline) == "\u{1B}[1m\u{1B}[4mx\u{1B}[24m\u{1B}[22m")
    #expect(style("a\nb", .bold) == "\u{1B}[1ma\u{1B}[22m\n\u{1B}[1mb\u{1B}[22m")
    #expect(style("a\r\nb", .bold) == "\u{1B}[1ma\u{1B}[22m\r\n\u{1B}[1mb\u{1B}[22m")
    #expect(style(style("x", .dim), .bold) == "\u{1B}[1m\u{1B}[2mx\u{1B}[22m\u{1B}[1m\u{1B}[22m")
    #expect(TerminalStyle.plain("x", .red) == "x")
    #expect(TerminalStyle(.ansi256)("!", .orange) == "\u{1B}[38;5;214m!\u{1B}[39m")
  }

  @Test("colour support follows FORCE_COLOR, NO_COLOR, TERM and COLORTERM")
  func detection() {
    #expect(ColorSupport.detect(isTerminal: false, environment: [:]) == .none)
    #expect(ColorSupport.detect(isTerminal: true, environment: ["TERM": "xterm"]) == .basic)
    #expect(ColorSupport.detect(isTerminal: true, environment: ["TERM": "xterm-256color"]) == .ansi256)
    #expect(ColorSupport.detect(isTerminal: true, environment: ["COLORTERM": "truecolor"]) == .trueColor)
    #expect(ColorSupport.detect(isTerminal: true, environment: ["NO_COLOR": "1"]) == .none)
    #expect(ColorSupport.detect(isTerminal: false, environment: ["FORCE_COLOR": "3"]) == .trueColor)
    #expect(ColorSupport.detect(isTerminal: true, environment: ["TERM": "dumb"]) == .none)
  }
}
