import Foundation
import Logging
import MCP

/// Wraps a transport so the server answers one request at a time, in arrival order, and the session ends only
/// after every request has been answered.
///
/// The SDK's server handles each incoming request in a task of its own. A client that pipelines requests (sends
/// several without waiting for the answers) would have them run concurrently and in no particular order: an
/// `add` sent right after `create_list` could look for the list before it exists. This transport passes the
/// server one message at a time and holds the next back until every request it has passed on so far has been
/// answered, so each tool sees the effects of the ones before it. Notifications don't wait.
///
/// The SDK's server also stops as soon as its input ends, while requests it received just before may still be
/// running. For stdio that means a client that writes its requests and closes stdin
/// (`printf … | reminders --mcp`) could lose the last answers. The end of input is held back too, until every
/// request has been answered.
///
/// `patience` bounds both waits, so a request that is never answered can't stall the session for good.
public actor SerialTransport: Transport {
  public nonisolated let logger: Logger
  private let base: any Transport
  private let patience: Duration
  private var unanswered = Set<String>()
  private var inputEnded = false
  private var output: AsyncThrowingStream<Data, any Error>.Continuation?
  /// The forwarding loop, while it waits for the server to answer what it was given.
  private var waiting: CheckedContinuation<Void, Never>?
  private var tasks: [Task<Void, Never>] = []

  public init(_ base: any Transport, patience: Duration = .seconds(60)) {
    self.base = base
    self.patience = patience
    logger = Logger(label: "reminders.mcp.transport", factory: { _ in SwiftLogNoOpLogHandler() })
  }

  public func connect() async throws {
    try await base.connect()
  }

  public func disconnect() async {
    tasks.forEach { $0.cancel() }
    resumeForwarding()
    await base.disconnect()
  }

  public func send(_ data: Data) async throws {
    // Count the answer even if sending it fails, so the next request isn't held back for nothing.
    defer {
      unanswered.subtract(Self.ids(in: data, ofRequests: false))
      if unanswered.isEmpty { resumeForwarding() }
      finishIfDrained()
    }
    try await base.send(data)
  }

  public func receive() -> AsyncThrowingStream<Data, any Error> {
    let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
    output = continuation
    tasks.append(Task { await forward(to: continuation) })
    return stream
  }

  private func forward(to continuation: AsyncThrowingStream<Data, any Error>.Continuation) async {
    do {
      for try await message in await base.receive() {
        unanswered.formUnion(Self.ids(in: message, ofRequests: true))
        continuation.yield(message)
        await waitUntilAnswered()
      }
    } catch {
      continuation.finish(throwing: error)
      return
    }
    inputEnded = true
    finishIfDrained()
    let patience = patience
    tasks.append(
      Task {
        try? await Task.sleep(for: patience)
        finish()
      })
  }

  /// Suspends until every request passed on so far has been answered, or `patience` has passed.
  private func waitUntilAnswered() async {
    guard !unanswered.isEmpty, !Task.isCancelled else { return }
    let patience = patience
    let timeout = Task {
      try? await Task.sleep(for: patience)
      if !Task.isCancelled { resumeForwarding() }
    }
    await withCheckedContinuation { waiting = $0 }
    timeout.cancel()
  }

  private func resumeForwarding() {
    waiting?.resume()
    waiting = nil
  }

  private func finishIfDrained() {
    if inputEnded && unanswered.isEmpty { finish() }
  }

  private func finish() {
    output?.finish()
    output = nil
  }

  /// The JSON-RPC ids of the requests (or of the responses) in a message or batch.
  static func ids(in data: Data, ofRequests requests: Bool) -> Set<String> {
    guard let value = try? JSONDecoder().decode(Value.self, from: data) else { return [] }
    let messages = value.arrayValue ?? [value]
    return Set(
      messages.compactMap { message -> String? in
        guard let object = message.objectValue, let id = object["id"], !id.isNull else { return nil }
        let isRequest = object["method"] != nil
        return isRequest == requests ? id.description : nil
      })
  }
}
