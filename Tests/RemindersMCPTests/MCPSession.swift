import Foundation
import MCP
import RemindersCore
import Testing

@testable import RemindersMCP

func day(_ text: String) -> CalendarDay { CalendarDay(text)! }

/// 2026-10-23 10:00 UTC.
let referenceInstant = Date(timeIntervalSince1970: 1_792_749_600)
let utcClock = DayClock(now: referenceInstant, timeZone: .gmt)

/// Groceries and Work, with reminders overdue, due today, tomorrow, next week, undated and completed.
func makeStore(access: ReminderAccess = .fullAccess) -> InMemoryReminderStore {
  InMemoryReminderStore(
    lists: [ReminderList(id: "W", title: "Work"), ReminderList(id: "G", title: "Groceries")],
    reminders: [
      Reminder(id: "G1", title: "Buy milk", listID: "G", listName: "Groceries", dueDate: day("2026-10-23")),
      Reminder(id: "G2", title: "Buy bread", listID: "G", listName: "Groceries", dueDate: day("2026-10-20")),
      Reminder(id: "G3", title: "Buy eggs", isCompleted: true, listID: "G", listName: "Groceries"),
      Reminder(
        id: "W1", title: "Write report", listID: "W", listName: "Work", dueDate: day("2026-10-24"),
        notes: "Quarterly numbers"),
      Reminder(id: "W2", title: "Plan offsite", listID: "W", listName: "Work", dueDate: day("2026-10-30")),
    ], access: access, now: { referenceInstant })
}

/// An MCP client connected to a `reminders` server over the SDK's in-memory transport.
struct MCPSession {
  let client: Client
  let server: Server
  let store: InMemoryReminderStore

  static func start(
    store: InMemoryReminderStore = makeStore(), permissions: PermissionGuidance = PermissionGuidance(host: nil)
  ) async throws -> MCPSession {
    let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
    let server = try await RemindersMCPServer(
      service: RemindersService(store: store, clock: utcClock, permissions: permissions)
    )
    .start(on: serverTransport)
    let client = Client(name: "tests", version: "1.0")
    try await client.connect(transport: clientTransport)
    return MCPSession(client: client, server: server, store: store)
  }

  func stop() async {
    await client.disconnect()
    await server.stop()
  }

  /// `tools/call`, with the full result (the SDK's convenience drops `structuredContent`).
  func call(_ name: String, _ arguments: [String: Value] = [:]) async throws -> CallTool.Result {
    try await client.send(CallTool.request(.init(name: name, arguments: arguments))).value
  }

  /// A call that must succeed; returns its structured content.
  func success(_ name: String, _ arguments: [String: Value] = [:]) async throws -> [String: Value] {
    let result = try await call(name, arguments)
    #expect(result.isError == false, "\(name) failed: \(result.content)")
    let structured = try #require(result.structuredContent?.objectValue)
    // The text content is the same JSON, for clients that don't read structured content.
    let text = try #require(result.content.first.flatMap(Self.text))
    #expect(try JSONDecoder().decode(Value.self, from: Data(text.utf8)) == result.structuredContent)
    return structured
  }

  /// A call that must fail as a tool error; returns its error object.
  func failure(_ name: String, _ arguments: [String: Value] = [:]) async throws -> RemindersError {
    let result = try await call(name, arguments)
    #expect(result.isError == true, "\(name) unexpectedly succeeded")
    #expect(result.structuredContent == nil)
    let text = try #require(result.content.first.flatMap(Self.text))
    return try JSONDecoder().decode(ErrorBody.self, from: Data(text.utf8)).error
  }

  func titles(_ name: String, _ arguments: [String: Value] = [:]) async throws -> [String] {
    let reminders = try await success(name, arguments)["reminders"]?.arrayValue ?? []
    return reminders.compactMap { $0.objectValue?["title"]?.stringValue }
  }

  private struct ErrorBody: Decodable {
    let error: RemindersError
  }

  private static func text(_ content: Tool.Content) -> String? {
    if case .text(let text, _, _) = content { return text }
    return nil
  }
}

/// Checks a value against the subset of JSON Schema the tool schemas use: type, required, properties, items, enum
/// and additionalProperties.
func violations(of value: Value, against schema: Value, at path: String = "$") -> [String] {
  guard let schema = schema.objectValue else { return [] }
  var problems: [String] = []
  if let allowed = schema["enum"]?.arrayValue, !allowed.contains(value) { problems.append("\(path): not in enum") }
  switch schema["type"]?.stringValue {
  case "object":
    guard let object = value.objectValue else { return ["\(path): expected object"] }
    let properties = schema["properties"]?.objectValue ?? [:]
    for key in schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [] where object[key] == nil {
      problems.append("\(path).\(key): missing")
    }
    for (key, child) in object {
      if let childSchema = properties[key] {
        problems += violations(of: child, against: childSchema, at: "\(path).\(key)")
      } else if schema["additionalProperties"]?.boolValue == false {
        problems.append("\(path).\(key): not allowed")
      }
    }
  case "array":
    guard let items = value.arrayValue else { return ["\(path): expected array"] }
    for (index, item) in items.enumerated() {
      problems += violations(of: item, against: schema["items"] ?? [:], at: "\(path)[\(index)]")
    }
  case "string": if value.stringValue == nil { problems.append("\(path): expected string") }
  case "integer": if value.intValue == nil { problems.append("\(path): expected integer") }
  case "boolean": if value.boolValue == nil { problems.append("\(path): expected boolean") }
  default: break
  }
  return problems
}
