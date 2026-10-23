import MCP
import RemindersCore

/// A tool call's arguments, checked against the tool's input schema: unknown and missing arguments, and values of
/// the wrong type, are `INVALID_ARGUMENT` errors that name the argument.
struct ToolArguments: Sendable {
  private let values: [String: Value]
  private let toolName: String

  init(_ values: [String: Value]?, for tool: ReminderTool) throws(RemindersError) {
    let values = (values ?? [:]).filter { !$0.value.isNull }
    let schema = tool.inputSchema
    let allowed = JSONSchema.propertyNames(of: schema)
    if let unknown = values.keys.sorted().first(where: { !allowed.contains($0) }) {
      throw Self.invalid(
        "Unknown argument \"\(unknown)\" for \(tool.rawValue)",
        expected: allowed.isEmpty ? "it takes no arguments" : "expected: \(allowed.sorted().joined(separator: ", "))")
    }
    if let missing = JSONSchema.requiredNames(of: schema).first(where: { values[$0] == nil }) {
      throw Self.invalid("Missing required argument \"\(missing)\" for \(tool.rawValue)")
    }
    self.values = values
    self.toolName = tool.rawValue
  }

  /// A string argument the schema requires.
  func string(_ key: String) throws(RemindersError) -> String {
    guard let value = try optionalString(key) else { throw Self.invalid("Missing required argument \"\(key)\"") }
    return value
  }

  func optionalString(_ key: String) throws(RemindersError) -> String? {
    guard let value = values[key] else { return nil }
    guard let string = value.stringValue else { throw typeMismatch(key, "a string") }
    return string
  }

  func bool(_ key: String) throws(RemindersError) -> Bool? {
    guard let value = values[key] else { return nil }
    guard let bool = value.boolValue else { throw typeMismatch(key, "true or false") }
    return bool
  }

  /// Integers, and numbers with no fractional part (some clients send every number as a double).
  func integer(_ key: String) throws(RemindersError) -> Int? {
    guard let value = values[key] else { return nil }
    if let int = value.intValue { return int }
    if let double = value.doubleValue, double.rounded() == double, let int = Int(exactly: double) { return int }
    throw typeMismatch(key, "an integer")
  }

  func priority(_ key: String) throws(RemindersError) -> Priority? {
    guard let text = try optionalString(key) else { return nil }
    guard let priority = Priority(rawValue: text) else {
      throw Self.invalid(
        "Invalid \"\(key)\" \"\(text)\"",
        expected: "expected one of: \(Priority.allCases.map(\.rawValue).joined(separator: ", "))")
    }
    return priority
  }

  private func typeMismatch(_ key: String, _ expected: String) -> RemindersError {
    Self.invalid("Argument \"\(key)\" for \(toolName) must be \(expected)")
  }

  private static func invalid(_ message: String, expected: String? = nil) -> RemindersError {
    RemindersError(.invalidArgument, message, suggestion: expected.map { "Check the tool's input schema: \($0)" })
  }
}
