import Foundation
import MCP
import RemindersCore

/// Runs tool calls against a ``RemindersService``: the same operations, matching and errors as the CLI.
///
/// A successful call returns its result as `structuredContent` (an object matching the tool's output schema) and
/// as pretty-printed JSON text. A failed call is a tool error (`isError: true`) whose text is
/// `{"error": {"code", "message", "suggestion"}}`, so the model can read the code and correct itself.
public struct RemindersToolbox: Sendable {
  public var service: RemindersService

  public init(service: RemindersService) {
    self.service = service
  }

  public static var tools: [Tool] { ReminderTool.allCases.map(\.definition) }

  /// Handles `tools/call`. An unknown tool name is a protocol error; everything else is a tool result.
  public func call(_ name: String, arguments: [String: Value]?) async throws(MCPError) -> CallTool.Result {
    guard let tool = ReminderTool(rawValue: name) else { throw MCPError.invalidParams("Unknown tool: \(name)") }
    do {
      let output = try await perform(tool, ToolArguments(arguments, for: tool))
      return try Self.success(output)
    } catch let error as RemindersError {
      return Self.failure(error)
    } catch {
      return Self.failure(RemindersError(wrapping: error))
    }
  }

  private func perform(_ tool: ReminderTool, _ arguments: ToolArguments) async throws(RemindersError)
    -> any Encodable & Sendable
  {
    switch tool {
    case .lists:
      return ListsResult(lists: try await service.lists())
    case .list:
      let listing = try await service.contents(
        ofList: arguments.string("list"),
        section: arguments.optionalString("section").flatMap { $0.isEmpty ? nil : $0 },
        includeCompleted: arguments.bool("includeCompleted") ?? false)
      return RemindersResult(listing)
    case .createList:
      return try await service.createList(named: arguments.string("name"))
    case .deleteList:
      return try await service.deleteList(named: arguments.string("list"))
    case .add:
      return try await service.add(
        NewReminderRequest(
          list: arguments.string("list"), title: arguments.string("title"), due: arguments.optionalString("due"),
          priority: arguments.priority("priority") ?? .none, notes: arguments.optionalString("notes"),
          repeatRule: arguments.optionalString("repeat"),
          section: arguments.optionalString("section").flatMap { $0.isEmpty ? nil : $0 }))
    case .complete:
      return try await service.complete(reference(arguments, for: tool))
    case .delete:
      return try await service.delete(reference(arguments, for: tool))
    case .update:
      let edit = ReminderEdit(
        title: try arguments.optionalString("newTitle"), due: try arguments.optionalString("due"),
        clearDue: try arguments.bool("clearDue") ?? false, priority: try arguments.priority("priority"),
        notes: try arguments.optionalString("notes"))
      return try await service.update(reference(arguments, for: tool), edit)
    case .sections:
      return SectionsResult(sections: try await service.sections(ofList: arguments.string("list")).sections)
    case .createSection:
      return try await service.createSection(named: arguments.string("name"), inList: arguments.string("list"))
    case .deleteSection:
      return try await service.deleteSection(named: arguments.string("name"), inList: arguments.string("list"))
    case .move:
      return try await service.move(reference(arguments, for: tool), toSection: arguments.string("toSection"))
    case .today:
      return RemindersResult(try await service.dueToday())
    case .overdue:
      return RemindersResult(try await service.overdue())
    case .upcoming:
      return RemindersResult(try await service.upcoming(days: arguments.integer("days") ?? 7))
    case .search:
      return RemindersResult(try await service.search(arguments.string("query")))
    }
  }

  /// The reminder a tool names: by `title`, or by `id` prefix, which wins when both are given.
  private func reference(_ arguments: ToolArguments, for tool: ReminderTool) throws(RemindersError)
    -> ReminderReference
  {
    let title = try arguments.optionalString("title").flatMap { $0.isEmpty ? nil : $0 }
    let id = try arguments.optionalString("id").flatMap { $0.isEmpty ? nil : $0 }
    guard title != nil || id != nil else {
      throw RemindersError(
        .invalidArgument, "\(tool.rawValue) needs \"title\" or \"id\" to find the reminder",
        suggestion: "Pass the reminder's title (fuzzy matched) or an ID prefix")
    }
    return ReminderReference(list: try arguments.string("list"), title: title ?? "", id: id)
  }

  // MARK: Results

  private static func success(_ output: any Encodable & Sendable) throws -> CallTool.Result {
    let data = try JSONEncoder.reminders().encode(output)
    let structured: Value? = try JSONDecoder().decode(Value.self, from: data)
    return CallTool.Result(
      content: [.text(text: String(bytes: data, encoding: .utf8) ?? "", annotations: nil, _meta: nil)],
      structuredContent: structured, isError: false)
  }

  static func failure(_ error: RemindersError) -> CallTool.Result {
    let text = (try? JSONEncoder.reminders().encode(ErrorPayload(error: error))).flatMap {
      String(bytes: $0, encoding: .utf8)
    }
    return CallTool.Result(content: [.text(text: text ?? error.message, annotations: nil, _meta: nil)], isError: true)
  }
}

private struct ErrorPayload: Encodable {
  let error: RemindersError
}

/// `reminders_lists`: `{"lists": [...]}` (MCP structured results are objects).
private struct ListsResult: Encodable, Sendable {
  let lists: [ReminderList]
}

/// `reminders_sections`: `{"sections": [...]}`.
private struct SectionsResult: Encodable, Sendable {
  let sections: [Section]
}

/// Reminder queries: `{"reminders": [...]}`.
private struct RemindersResult: Encodable, Sendable {
  let reminders: [Reminder]

  init(_ listing: ReminderListing) {
    reminders = listing.reminders
  }
}
