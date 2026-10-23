// Opt-in, like LifecycleTests: REMINDERS_INTEGRATION=1 swift test --filter RemindersIntegrationTests
//
// These talk to Apple Reminders through EventKitReminderStore directly, and through `reminders --mcp`, checking
// that each change is visible to the very next call. They only touch a throwaway `_reminders_test_<hex>` list.

#if canImport(EventKit)
  import Foundation
  import RemindersApple
  import RemindersCore
  import Testing

  private let isEnabled = ProcessInfo.processInfo.environment["REMINDERS_INTEGRATION"] == "1"

  private func throwawayName() -> String {
    "_reminders_test_" + String(UInt32.random(in: 0...0xFF_FFFF), radix: 16)
  }

  @Suite(
    "Apple Reminders store", .serialized,
    .enabled(if: isEnabled, "Set REMINDERS_INTEGRATION=1 to run against Apple Reminders (uses a throwaway list)"))
  struct EventKitStoreTests {
    @Test("the store sees its own writes immediately")
    func readsItsOwnWrites() async throws {
      let store = EventKitReminderStore()
      #expect(try await store.requestFullAccess() == .fullAccess)
      let name = throwawayName()
      // A failed run leaves the list behind; LifecycleTests removes leftover test lists.
      let listID = try await store.createList(title: name)

      #expect(await store.lists().contains { $0.id == listID && $0.title == name })
      let id = try await store.createReminder(ReminderDraft(title: "Seen at once", listID: listID))
      #expect(try await store.reminders(inLists: [listID], .incomplete).map(\.id) == [id])

      try await store.updateReminder(id: id, ReminderChanges(title: "Renamed at once"))
      #expect(try await store.reminders(inLists: [listID], .incomplete).map(\.title) == ["Renamed at once"])

      try await store.completeReminder(id: id)
      #expect(try await store.reminders(inLists: [listID], .incomplete).isEmpty)
      #expect(try await store.reminders(inLists: [listID], .completed).map(\.id) == [id])

      try await store.deleteList(id: listID)
      #expect(await !store.lists().contains { $0.id == listID })
      await #expect(throws: RemindersError.self) { try await store.reminders(inLists: [listID], .incomplete) }
    }

    @Test("reminders --mcp answers pipelined calls in order, each seeing the one before")
    func pipelinedMCP() async throws {
      let binary = try remindersBinary()
      let name = throwawayName()
      let requests = [
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"tests","version":"1"}}}"#,
        #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
        call(3, "reminders_create_list", #"{"name":"\#(name)"}"#),
        call(4, "reminders_add", #"{"list":"\#(name)","title":"Pipelined"}"#),
        call(5, "reminders_list", #"{"list":"\#(name)"}"#),
        call(6, "reminders_delete_list", #"{"list":"\#(name)"}"#),
      ]
      let process = Process()
      process.executableURL = binary
      process.arguments = ["--mcp"]
      let input = Pipe()
      let output = Pipe()
      process.standardInput = input
      process.standardOutput = output
      process.standardError = FileHandle.nullDevice
      try process.run()
      // All at once, then end of input: the server must still answer everything, in order.
      input.fileHandleForWriting.write(Data((requests.joined(separator: "\n") + "\n").utf8))
      try input.fileHandleForWriting.close()
      let data = output.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()

      let answers = String(bytes: data, encoding: .utf8)?.split(separator: "\n").compactMap { line in
        (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
      }
      let ids = answers?.compactMap { $0["id"] as? Int }
      #expect(ids == [1, 3, 4, 5, 6])
      for answer in answers ?? [] where (answer["id"] as? Int ?? 0) >= 3 {
        let result = answer["result"] as? [String: Any]
        #expect(result?["isError"] as? Bool != true, "\(answer)")
      }
      let listed = (answers?.first { $0["id"] as? Int == 5 }?["result"] as? [String: Any])?["structuredContent"]
      let titles = ((listed as? [String: Any])?["reminders"] as? [[String: Any]])?.compactMap { $0["title"] as? String }
      #expect(titles == ["Pipelined"])
    }
  }

  private func call(_ id: Int, _ tool: String, _ arguments: String) -> String {
    #"{"jsonrpc":"2.0","id":\#(id),"method":"tools/call","params":{"name":"\#(tool)","arguments":\#(arguments)}}"#
  }
#endif
