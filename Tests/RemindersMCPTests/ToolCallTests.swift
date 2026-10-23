import Foundation
import MCP
import RemindersCore
import Testing

@testable import RemindersMCP

@Suite("MCP tool calls")
struct ToolCallTests {
  @Test("queries return structured reminders matching the output schemas")
  func queries() async throws {
    let session = try await MCPSession.start()
    let lists = try await session.success("reminders_lists")
    #expect(lists["lists"]?.arrayValue?.compactMap { $0.objectValue?["title"]?.stringValue } == ["Groceries", "Work"])
    #expect(lists["lists"]?.arrayValue?.first?.objectValue?["reminderCount"] == 2)
    // Only "Buy bread" (due 2026-10-20) is overdue; "Buy milk" is due today.
    #expect(lists["lists"]?.arrayValue?.first?.objectValue?["overdueCount"] == 1)

    // Earliest due first, as in the CLI's text and JSON.
    #expect(try await session.titles("reminders_list", ["list": "groc"]) == ["Buy bread", "Buy milk"])
    #expect(
      try await session.titles("reminders_list", ["list": "Groceries", "includeCompleted": true]).contains("Buy eggs"))
    #expect(try await session.titles("reminders_today") == ["Buy milk"])
    #expect(try await session.titles("reminders_overdue") == ["Buy bread"])
    #expect(
      Set(try await session.titles("reminders_upcoming", ["days": 1])) == ["Buy milk", "Write report"])
    #expect(try await session.titles("reminders_upcoming").count == 3)
    #expect(try await session.titles("reminders_search", ["query": "QUARTERLY"]) == ["Write report"])

    for (name, arguments) in [
      ("reminders_lists", [:]), ("reminders_list", ["list": "Work"]), ("reminders_today", [:]),
      ("reminders_search", ["query": "buy"]),
    ] as [(String, [String: Value])] {
      let result = try await session.call(name, arguments)
      let schema = try #require(ReminderTool(rawValue: name)?.outputSchema)
      #expect(violations(of: try #require(result.structuredContent), against: schema).isEmpty, "\(name)")
    }
    await session.stop()
  }

  @Test("add, complete, update and delete change the store through the service")
  func changes() async throws {
    let session = try await MCPSession.start()
    let added = try await session.success(
      "reminders_add",
      ["list": "work", "title": "Ship it", "due": "tomorrow", "priority": "high", "notes": "v1", "repeat": "weekly"])
    #expect(added["message"] == "Added \"Ship it\" to \"Work\" (repeats weekly)")
    let id = try #require(added["id"]?.stringValue)
    let shipped = try #require(await session.store.allReminders.first { $0.id == id })
    #expect(shipped.dueDate == day("2026-10-24"))
    #expect(shipped.priority == .high)
    #expect(shipped.recurrence == Recurrence(.weekly))

    let completed = try await session.success("reminders_complete", ["list": "Groceries", "title": "milk"])
    #expect(completed["message"] == "Completed \"Buy milk\" in \"Groceries\"")
    #expect(await session.store.allReminders.first { $0.id == "G1" }?.isCompleted == true)

    _ = try await session.success(
      "reminders_update", ["list": "Work", "title": "Write report", "newTitle": "Write the report", "clearDue": true])
    let report = try #require(await session.store.allReminders.first { $0.id == "W1" })
    #expect(report.title == "Write the report")
    #expect(report.dueDate == nil)

    // title or id: an ID prefix alone is enough.
    _ = try await session.success("reminders_update", ["list": "Work", "id": "w2", "priority": "low"])
    #expect(await session.store.allReminders.first { $0.id == "W2" }?.priority == .low)
    let byID = try await session.success("reminders_complete", ["list": "Work", "id": "W2"])
    #expect(byID["message"] == "Completed \"Plan offsite\" in \"Work\"")

    // No confirmation step over MCP; clients confirm destructive tools themselves.
    let deleted = try await session.success("reminders_delete", ["list": "Groceries", "title": "x", "id": "g2"])
    #expect(deleted["message"] == "Deleted \"Buy bread\" from \"Groceries\"")
    #expect(await !session.store.allReminders.contains { $0.id == "G2" })
    await session.stop()
  }

  @Test("create-list is idempotent and delete-list removes the list")
  func listChanges() async throws {
    let session = try await MCPSession.start()
    let created = try await session.success("reminders_create_list", ["name": "Garden"])
    let again = try await session.success("reminders_create_list", ["name": "Garden"])
    #expect(created["id"] == again["id"])
    #expect(created["message"] == "Created list \"Garden\"")
    let deleted = try await session.success("reminders_delete_list", ["list": "gard"])
    #expect(deleted["message"] == "Deleted list \"Garden\"")
    #expect(try await session.store.lists().map(\.title) == ["Work", "Groceries"])
    await session.stop()
  }

  @Test("store and lookup failures are tool errors with the CLI's codes")
  func errors() async throws {
    let session = try await MCPSession.start()
    let missingList = try await session.failure("reminders_list", ["list": "Garden"])
    #expect(missingList.code == .listNotFound)
    let missingReminder = try await session.failure("reminders_complete", ["list": "Work", "title": "Nothing"])
    #expect(missingReminder.code == .reminderNotFound)
    let badDate = try await session.failure("reminders_add", ["list": "Work", "title": "X", "due": "2026-02-30"])
    #expect(badDate.code == .invalidArgument)
    #expect(await session.store.allReminders.count == 5)
    await session.stop()
  }

  @Test("arguments are checked against the input schema")
  func argumentValidation() async throws {
    let session = try await MCPSession.start()
    let cases: [(String, [String: Value], String)] = [
      ("reminders_list", [:], "Missing required argument \"list\""),
      ("reminders_list", ["list": "Work", "includeCompleted": "yes"], "must be true or false"),
      ("reminders_upcoming", ["days": "soon"], "must be an integer"),
      ("reminders_add", ["list": "Work", "title": "X", "priority": "urgent"], "Invalid \"priority\""),
      ("reminders_lists", ["verbose": true], "Unknown argument \"verbose\""),
      ("reminders_search", ["query": 3], "must be a string"),
      ("reminders_complete", ["list": "Work"], "needs \"title\" or \"id\""),
      ("reminders_delete", ["list": "Work", "title": ""], "needs \"title\" or \"id\""),
      ("reminders_update", ["list": "Work", "newTitle": "X"], "needs \"title\" or \"id\""),
    ]
    for (name, arguments, message) in cases {
      let error = try await session.failure(name, arguments)
      #expect(error.code == .invalidArgument, "\(name)")
      #expect(error.message.contains(message), "\(name): \(error.message)")
    }
    // Whole doubles are accepted as integers; null means absent.
    #expect(try await session.titles("reminders_upcoming", ["days": 1.0]).count == 2)
    #expect(try await session.titles("reminders_list", ["list": "Work", "includeCompleted": .null]).count == 2)
    await session.stop()
  }

  @Test("section tools and the section argument report NOT_IMPLEMENTED")
  func sections() async throws {
    let session = try await MCPSession.start()
    let calls: [(String, [String: Value])] = [
      ("reminders_sections", ["list": "Work"]), ("reminders_create_section", ["list": "Work", "name": "Q4"]),
      ("reminders_delete_section", ["list": "Work", "name": "Q4"]),
      ("reminders_move", ["list": "Work", "title": "Write report", "toSection": "Q4"]),
      ("reminders_add", ["list": "Work", "title": "X", "section": "Q4"]),
    ]
    for (name, arguments) in calls {
      #expect(try await session.failure(name, arguments).code == .notImplemented, "\(name)")
    }
    #expect(await session.store.allReminders.count == 5)
    await session.stop()
  }

  @Test("permission problems surface as PERMISSION_DENIED naming the client app")
  func permission() async throws {
    let claude = PermissionGuidance(host: HostApplication(name: "Claude", bundlePath: "/Applications/Claude.app"))
    let denied = try await MCPSession.start(store: makeStore(access: .denied), permissions: claude)
    let error = try await denied.failure("reminders_today")
    #expect(error.code == .permissionDenied)
    #expect(error.message == "Reminders access not granted (Denied for Claude)")
    #expect(error.suggestion?.hasPrefix("Enable Claude in System Settings > Privacy & Security > Reminders") == true)
    await denied.stop()

    let unprompted = InMemoryReminderStore(access: .notDetermined, promptAnswer: .notDetermined)
    let silent = try await MCPSession.start(store: unprompted, permissions: claude)
    let refusal = try await silent.failure("reminders_lists")
    #expect(refusal.message == "Reminders access not granted (macOS didn't show the prompt for Claude)")
    await silent.stop()
  }

  @Test("an unknown tool is a JSON-RPC invalid-params error")
  func unknownTool() async throws {
    let session = try await MCPSession.start()
    await #expect(throws: MCPError.self) { try await session.call("lists") }
    do {
      _ = try await session.call("reminders_nope")
    } catch let error as MCPError {
      #expect(error.code == -32602)
    }
    await session.stop()
  }
}
