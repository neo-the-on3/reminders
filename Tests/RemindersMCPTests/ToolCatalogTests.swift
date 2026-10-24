import Foundation
import MCP
import RemindersCore
import Testing

@testable import RemindersMCP

@Suite("MCP tool catalog")
struct ToolCatalogTests {
  @Test("tools/list offers every tool with an object input schema")
  func listing() async throws {
    let session = try await MCPSession.start()
    let (tools, cursor) = try await session.client.listTools()
    #expect(cursor == nil)
    #expect(
      tools.map(\.name) == [
        "reminders_lists", "reminders_list", "reminders_create_list", "reminders_delete_list", "reminders_add",
        "reminders_complete", "reminders_delete", "reminders_update", "reminders_sections",
        "reminders_create_section", "reminders_delete_section", "reminders_move", "reminders_today",
        "reminders_overdue", "reminders_upcoming", "reminders_search",
      ])
    for tool in tools {
      let schema = try #require(tool.inputSchema.objectValue, "\(tool.name)")
      #expect(schema["type"] == "object")
      #expect(schema["additionalProperties"] == false)
      let properties = JSONSchema.propertyNames(of: tool.inputSchema)
      #expect(JSONSchema.requiredNames(of: tool.inputSchema).allSatisfy(properties.contains), "\(tool.name)")
      #expect(tool.description?.isEmpty == false)
      #expect(tool.outputSchema != nil, "\(tool.name)")
      if let output = tool.outputSchema { #expect(output.objectValue?["type"] == "object") }
    }
    await session.stop()
  }

  @Test("complete, delete and update take title or id, requiring neither")
  func titleOrID() {
    for tool in [ReminderTool.complete, .delete, .update] {
      #expect(JSONSchema.requiredNames(of: tool.inputSchema) == ["list"], "\(tool)")
      #expect(JSONSchema.propertyNames(of: tool.inputSchema).isSuperset(of: ["title", "id"]), "\(tool)")
    }
  }

  @Test("annotations mark queries read-only and deletions destructive")
  func annotations() {
    #expect(ReminderTool.search.definition.annotations.readOnlyHint == true)
    #expect(ReminderTool.lists.definition.annotations.readOnlyHint == true)
    #expect(ReminderTool.delete.definition.annotations.destructiveHint == true)
    #expect(ReminderTool.deleteList.definition.annotations.destructiveHint == true)
    #expect(ReminderTool.createList.definition.annotations.idempotentHint == true)
    #expect(ReminderTool.allCases.allSatisfy { $0.definition.annotations.openWorldHint == false })
  }

  @Test("the server identifies itself and only offers tools")
  func serverInfo() async throws {
    let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
    let server = await RemindersMCPServer(service: RemindersService(store: makeStore())).makeServer()
    try await server.start(transport: serverTransport)
    let client = Client(name: "tests", version: "1.0")
    let initialized = try await client.connect(transport: clientTransport)
    #expect(initialized.serverInfo.name == "reminders")
    #expect(initialized.serverInfo.version == ProductInfo.version)
    #expect(initialized.capabilities.tools != nil)
    #expect(initialized.capabilities.resources == nil)
    #expect(initialized.instructions?.contains("PERMISSION_DENIED") == true)
    await client.disconnect()
    await server.stop()
  }

  @Test("the draining transport tells requests from responses, in batches too")
  func messageIDs() {
    let request = Data(#"{"jsonrpc":"2.0","id":7,"method":"tools/list"}"#.utf8)
    let notification = Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)
    let batch = Data(#"[{"jsonrpc":"2.0","id":"a","method":"ping"},{"jsonrpc":"2.0","id":8,"result":{}}]"#.utf8)
    #expect(SerialTransport.ids(in: request, ofRequests: true).count == 1)
    #expect(SerialTransport.ids(in: request, ofRequests: false).isEmpty)
    #expect(SerialTransport.ids(in: notification, ofRequests: true).isEmpty)
    #expect(SerialTransport.ids(in: batch, ofRequests: true).count == 1)
    #expect(SerialTransport.ids(in: batch, ofRequests: false).count == 1)
    #expect(SerialTransport.ids(in: Data("not json".utf8), ofRequests: true).isEmpty)
  }
}
