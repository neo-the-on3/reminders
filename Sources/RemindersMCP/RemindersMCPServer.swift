import MCP
import RemindersCore

/// The `reminders --mcp` server: the ``ReminderTool``s over any MCP transport (stdio for clients such as Claude).
public struct RemindersMCPServer: Sendable {
  public var toolbox: RemindersToolbox

  public init(service: RemindersService) {
    toolbox = RemindersToolbox(service: service)
  }

  static let instructions = """
    Manage Apple Reminders: lists, reminders, due dates, priorities and recurrence. List and reminder names are \
    fuzzy matched. Errors come back as {"error": {"code", "message", "suggestion"}}; PERMISSION_DENIED means macOS \
    hasn't given Reminders access to this server (or to the app that started it); show the user the error's \
    suggestion, which names what to allow and says how. Sections can be listed and filtered by (they need Full \
    Disk Access); creating, deleting and moving into sections are not implemented yet.
    """

  /// A configured server, not yet started.
  public func makeServer() async -> Server {
    let server = Server(
      name: ProductInfo.name, version: ProductInfo.version, title: "Apple Reminders",
      instructions: Self.instructions, capabilities: .init(tools: .init(listChanged: false)))
    let toolbox = toolbox
    await server.withMethodHandler(ListTools.self) { _ in ListTools.Result(tools: RemindersToolbox.tools) }
    await server.withMethodHandler(CallTool.self) { parameters in
      try await toolbox.call(parameters.name, arguments: parameters.arguments)
    }
    return server
  }

  /// A server answering on `transport`, one request at a time in arrival order (see ``SerialTransport``).
  public func start(on transport: any Transport) async throws -> Server {
    let server = await makeServer()
    try await server.start(transport: SerialTransport(transport))
    return server
  }

  /// Serves on `transport` until the client disconnects (for stdio: until stdin closes).
  public func run(on transport: any Transport) async throws {
    let server = try await start(on: transport)
    await server.waitUntilCompleted()
    await server.stop()
  }
}
