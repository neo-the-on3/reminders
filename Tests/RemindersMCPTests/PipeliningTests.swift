import Foundation
import MCP
import RemindersCore
import Synchronization
import Testing

@testable import RemindersMCP

/// The in-memory store, with a pause before every change takes effect, like a store that writes to disk.
private actor SlowStore: ReminderStore {
  let base: InMemoryReminderStore
  let pause: Duration

  init(_ base: InMemoryReminderStore, pause: Duration = .milliseconds(150)) {
    self.base = base
    self.pause = pause
  }

  private func wait() async { try? await Task.sleep(for: pause) }

  func accessStatus() async -> ReminderAccess { await base.accessStatus() }
  func requestFullAccess() async throws(RemindersError) -> ReminderAccess { await base.requestFullAccess() }
  func lists() async throws(RemindersError) -> [ReminderList] { try await base.lists() }
  func reminders(inLists listIDs: [String]?, _ filter: CompletionFilter) async throws(RemindersError) -> [Reminder] {
    try await base.reminders(inLists: listIDs, filter)
  }
  func createReminder(_ draft: ReminderDraft) async throws(RemindersError) -> String {
    await wait()
    return try await base.createReminder(draft)
  }
  func updateReminder(id: String, _ changes: ReminderChanges) async throws(RemindersError) {
    await wait()
    try await base.updateReminder(id: id, changes)
  }
  func completeReminder(id: String) async throws(RemindersError) {
    await wait()
    try await base.completeReminder(id: id)
  }
  func deleteReminder(id: String) async throws(RemindersError) {
    await wait()
    try await base.deleteReminder(id: id)
  }
  func createList(title: String) async throws(RemindersError) -> String {
    await wait()
    return try await base.createList(title: title)
  }
  func deleteList(id: String) async throws(RemindersError) {
    await wait()
    try await base.deleteList(id: id)
  }
}

/// A JSON-RPC `tools/call` request.
private func call(_ id: Int, _ tool: String, _ arguments: [String: Value]) throws -> Data {
  let request: Value = [
    "jsonrpc": "2.0", "id": .int(id), "method": "tools/call",
    "params": ["name": .string(tool), "arguments": .object(arguments)],
  ]
  return try JSONEncoder().encode(request)
}

@Suite("Pipelined requests")
struct PipeliningTests {
  @Test("pipelined calls run in arrival order, each seeing the ones before it")
  func ordered() async throws {
    let store = SlowStore(makeStore())
    let (client, serverTransport) = await InMemoryTransport.createConnectedPair()
    let server = try await RemindersMCPServer(service: RemindersService(store: store, clock: utcClock))
      .start(on: serverTransport)
    try await client.connect()

    // Written back to back, without waiting for any answer.
    for request in [
      try call(3, "reminders_create_list", ["name": "Errands"]),
      try call(4, "reminders_add", ["list": "Errands", "title": "Post parcel"]),
      try call(5, "reminders_list", ["list": "Errands"]),
      try call(6, "reminders_complete", ["list": "Errands", "title": "Post parcel"]),
      try call(7, "reminders_list", ["list": "Errands", "includeCompleted": true]),
    ] {
      try await client.send(request)
    }

    var answers: [(id: Int, result: CallTool.Result)] = []
    for try await data in await client.receive() {
      let response = try JSONDecoder().decode(Response<CallTool>.self, from: data)
      guard case .number(let id) = response.id else { continue }
      answers.append((id, try response.result.get()))
      if answers.count == 5 { break }
    }
    await client.disconnect()
    await server.stop()

    #expect(answers.map(\.id) == [3, 4, 5, 6, 7])
    for answer in answers {
      #expect(answer.result.isError != true, "call \(answer.id): \(answer.result.content)")
    }
    let open = answers[2].result.structuredContent?.objectValue?["reminders"]?.arrayValue
    #expect(open?.compactMap { $0.objectValue?["title"]?.stringValue } == ["Post parcel"])
    let all = answers[4].result.structuredContent?.objectValue?["reminders"]?.arrayValue
    #expect(all?.first?.objectValue?["isCompleted"]?.boolValue == true)
  }
}

@Suite("Serial transport")
struct SerialTransportTests {
  @Test("holds the next request back until the previous one is answered; notifications pass")
  func holdsBack() async throws {
    let (client, server) = await InMemoryTransport.createConnectedPair()
    let serial = SerialTransport(server)
    try await serial.connect()
    try await client.connect()
    let notification = Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)
    try await client.send(try call(1, "reminders_lists", [:]))
    try await client.send(notification)
    try await client.send(try call(2, "reminders_lists", [:]))

    var received = await serial.receive().makeAsyncIterator()
    let first = try #require(try await received.next())
    #expect(SerialTransport.ids(in: first, ofRequests: true) == ["1"])

    let delivered = Mutex<[Data]>([])
    let rest = Task {
      while delivered.withLock({ $0.count }) < 2, let message = try await received.next() {
        delivered.withLock { $0.append(message) }
      }
    }
    try await Task.sleep(for: .milliseconds(150))
    #expect(delivered.withLock { $0.isEmpty }, "nothing passes until request 1 is answered")
    try await serial.send(Data(#"{"jsonrpc":"2.0","id":1,"result":{}}"#.utf8))
    try await rest.value
    #expect(delivered.withLock { $0.map { SerialTransport.ids(in: $0, ofRequests: true) } } == [[], ["2"]])
    await serial.disconnect()
    await client.disconnect()
  }
}
