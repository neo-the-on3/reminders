import Foundation
import Logging
import MCP

/// Wraps a transport so the session ends only after every request has been answered.
///
/// The SDK's server stops as soon as its input ends, while requests it received just before may still be running.
/// For stdio that means a client that writes its requests and closes stdin (`printf … | reminders --mcp`) can lose
/// the last answers. This transport holds the end of input back until each request seen so far has had its
/// response sent, or until `gracePeriod` has passed.
public actor DrainingTransport: Transport {
  public nonisolated let logger: Logger
  private let base: any Transport
  private let gracePeriod: Duration
  private var unanswered = Set<String>()
  private var inputEnded = false
  private var output: AsyncThrowingStream<Data, any Error>.Continuation?
  private var tasks: [Task<Void, Never>] = []

  public init(_ base: any Transport, gracePeriod: Duration = .seconds(60)) {
    self.base = base
    self.gracePeriod = gracePeriod
    logger = Logger(label: "reminders.mcp.transport", factory: { _ in SwiftLogNoOpLogHandler() })
  }

  public func connect() async throws {
    try await base.connect()
  }

  public func disconnect() async {
    tasks.forEach { $0.cancel() }
    await base.disconnect()
  }

  public func send(_ data: Data) async throws {
    try await base.send(data)
    unanswered.subtract(Self.ids(in: data, ofRequests: false))
    finishIfDrained()
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
      }
    } catch {
      continuation.finish(throwing: error)
      return
    }
    inputEnded = true
    finishIfDrained()
    let gracePeriod = gracePeriod
    tasks.append(
      Task {
        try? await Task.sleep(for: gracePeriod)
        finish()
      })
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
