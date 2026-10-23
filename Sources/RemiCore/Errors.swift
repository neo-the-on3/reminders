// Ported from remi src/core/errors.ts (MIT, Matthew O'Riordan).

/// Error codes for machine-readable error handling.
public enum ErrorCode: String, CaseIterable, Sendable, Codable {
  case permissionDenied = "PERMISSION_DENIED"
  case listNotFound = "LIST_NOT_FOUND"
  case reminderNotFound = "REMINDER_NOT_FOUND"
  case sectionNotFound = "SECTION_NOT_FOUND"
  case ambiguousReminder = "AMBIGUOUS_REMINDER"
  case reminderKitUnavailable = "REMINDERKIT_UNAVAILABLE"
  case dbNotFound = "DB_NOT_FOUND"
  case swiftNotFound = "SWIFT_NOT_FOUND"
  case swiftExecutionFailed = "SWIFT_EXECUTION_FAILED"
  case syncTriggerFailed = "SYNC_TRIGGER_FAILED"
  case invalidArgument = "INVALID_ARGUMENT"
  case unknown = "UNKNOWN"
}

/// Structured error with machine-readable code and human-readable suggestion.
///
/// `code` is a plain string (not ``ErrorCode``) because, as in remi, arbitrary codes can be reported.
public struct RemiError: Equatable, Sendable, Error {
  public var code: String
  public var message: String
  public var suggestion: String?

  public init(code: String, message: String, suggestion: String? = nil) {
    self.code = code
    self.message = message
    self.suggestion = suggestion
  }

  public init(code: ErrorCode, message: String, suggestion: String? = nil) {
    self.init(code: code.rawValue, message: message, suggestion: suggestion)
  }
}

extension RemiError: JSONValueConvertible {
  public var jsonValue: JSONValue {
    var fields: [(String, JSONValue)] = [("code", .string(code)), ("message", .string(message))]
    if let suggestion { fields.append(("suggestion", .string(suggestion))) }
    return .object(fields)
  }
}

/// Create a structured ``RemiError``.
public func createError(_ code: ErrorCode, _ message: String, _ suggestion: String? = nil) -> RemiError {
  RemiError(code: code, message: message, suggestion: suggestion)
}

/// A throwable remi error (the Swift counterpart of remi's `RemiCommandError`).
public struct RemiCommandError: Error, Equatable, Sendable, CustomStringConvertible {
  public let code: ErrorCode
  public let message: String
  public let suggestion: String?

  public init(_ code: ErrorCode, _ message: String, suggestion: String? = nil) {
    self.code = code
    self.message = message
    self.suggestion = suggestion
  }

  public func toRemiError() -> RemiError {
    RemiError(code: code, message: message, suggestion: suggestion)
  }

  public var description: String { message }
}
