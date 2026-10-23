import Foundation
import Synchronization

/// Somewhere text output goes.
public protocol TextSink: Sendable {
  func write(_ text: String)
}

/// The process's standard output or standard error, unbuffered.
public struct StandardStream: TextSink {
  public enum Stream: Sendable { case output, error }
  public let stream: Stream

  public init(_ stream: Stream) {
    self.stream = stream
  }

  public func write(_ text: String) {
    let handle: FileHandle = stream == .output ? .standardOutput : .standardError
    handle.write(Data(text.utf8))
  }
}

/// Collects output in memory (tests, and later the MCP server).
public final class TextBuffer: TextSink {
  private let storage = Mutex("")

  public init() {}

  public var text: String { storage.withLock { $0 } }

  public func write(_ text: String) {
    storage.withLock { $0 += text }
  }
}

/// A command result that can be shown either as text or, with `--json`, as the `data` of a success envelope.
public protocol ConsoleRepresentable: Encodable, Sendable {
  func text(using renderer: TextRenderer) -> String
}

/// Where commands send results and errors, in the format the user asked for.
///
/// With `--json`, results go to stdout as `{"success": true, "data": ...}` and errors to stderr as
/// `{"success": false, "error": {"code", "message", "suggestion"}}`, pretty-printed with sorted keys. A result that
/// is itself a failure (a failing `doctor` check, `authorize` without access) goes to stdout as
/// `{"success": false, "data": ..., "error": {...}}`.
public struct Console: Sendable {
  public enum Format: Sendable, Hashable {
    case text, json
  }

  public var format: Format
  public var renderer: TextRenderer
  public let output: any TextSink
  public let errors: any TextSink

  public init(
    format: Format = .text, renderer: TextRenderer = TextRenderer(), output: any TextSink, errors: any TextSink
  ) {
    self.format = format
    self.renderer = renderer
    self.output = output
    self.errors = errors
  }

  /// A console on stdout and stderr, with colour when stdout is a terminal that supports it.
  public static func standard(format: Format, verbose: Bool) -> Console {
    let support = ColorSupport.detect(
      isTerminal: isatty(STDOUT_FILENO) != 0, environment: ProcessInfo.processInfo.environment)
    return Console(
      format: format, renderer: TextRenderer(style: TerminalStyle(support), verbose: verbose),
      output: StandardStream(.output), errors: StandardStream(.error))
  }

  public var isJSON: Bool { format == .json }
  public var style: TerminalStyle { renderer.style }

  /// Shows a command's result. Pass `failure` when the result reports that the command failed: JSON then says
  /// `"success": false` and carries the error next to the data, while text shows the result alone, which already
  /// explains what went wrong. The caller still decides the exit status.
  public func show(_ value: some ConsoleRepresentable, failure: RemindersError? = nil) {
    switch (format, failure) {
    case (.text, _): output.write(value.text(using: renderer))
    case (.json, nil): output.write(Self.encode(SuccessEnvelope(data: value)))
    case (.json, let error?): output.write(Self.encode(PartialFailureEnvelope(data: value, error: error)))
    }
  }

  /// Reports a failed command.
  public func report(_ error: RemindersError) {
    switch format {
    case .text: errors.write(renderer.error(error))
    case .json: errors.write(Self.encode(FailureEnvelope(error: error)))
    }
  }

  /// Human-only narration, such as the steps `authorize` walks through. Suppressed with `--json`.
  public func narrate(_ text: String) {
    if format == .text { output.write(text) }
  }

  static func encode(_ value: some Encodable) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    do {
      return (String(bytes: try encoder.encode(value), encoding: .utf8) ?? "") + "\n"
    } catch {
      return #"{"success": false, "error": {"code": "UNKNOWN", "message": "Could not encode the result as JSON"}}"#
        + "\n"
    }
  }
}

private struct SuccessEnvelope<Data: Encodable>: Encodable {
  let success = true
  let data: Data
}

private struct PartialFailureEnvelope<Data: Encodable>: Encodable {
  let success = false
  let data: Data
  let error: RemindersError
}

private struct FailureEnvelope: Encodable {
  let success = false
  let error: RemindersError
}

// MARK: - Results

/// `reminders lists`
public struct ListOverview: ConsoleRepresentable {
  public var lists: [ReminderList]

  public init(_ lists: [ReminderList]) {
    self.lists = lists
  }

  public func encode(to encoder: any Encoder) throws { try lists.encode(to: encoder) }
  public func text(using renderer: TextRenderer) -> String { renderer.lists(lists) }
}

/// Reminders in a list, or across lists (`today`, `overdue`, `upcoming`, `search`), in the order the layout asks
/// for. Text and JSON show that same order.
public struct ReminderListing: ConsoleRepresentable {
  public var reminders: [Reminder]
  /// Title above the reminders, such as the list name or "Due Today".
  public var heading: String?
  public var layout: ReminderLayout

  public init(_ reminders: [Reminder], heading: String?, layout: ReminderLayout) {
    self.reminders = layout.sortByDueDate ? reminders.sortedByDueDate() : reminders
    self.heading = heading
    self.layout = layout
  }

  public func encode(to encoder: any Encoder) throws { try reminders.encode(to: encoder) }
  public func text(using renderer: TextRenderer) -> String {
    renderer.reminders(reminders, heading: heading, layout: layout)
  }
}

/// `reminders sections <list>`
public struct SectionListing: ConsoleRepresentable {
  public var sections: [Section]
  public var listName: String
  /// Reminder counts by section name, when known.
  public var counts: [String: Int]?

  public init(_ sections: [Section], listName: String, counts: [String: Int]? = nil) {
    self.sections = sections
    self.listName = listName
    self.counts = counts
  }

  public func encode(to encoder: any Encoder) throws { try sections.encode(to: encoder) }
  public func text(using renderer: TextRenderer) -> String {
    renderer.sections(sections, listName: listName, counts: counts)
  }
}

/// A completed action: "✓ Added "Milk" to "Groceries"", or `{"message": ..., "id": ...}` in JSON.
public struct Confirmation: ConsoleRepresentable {
  public var message: String
  /// Identifier of the created item, when there is one.
  public var id: String?

  public init(_ message: String, id: String? = nil) {
    self.message = message
    self.id = id
  }

  public func text(using renderer: TextRenderer) -> String { renderer.confirmation(message) }
}
