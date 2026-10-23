/// An error every command reports the same way: a stable machine-readable ``Code``, a message for people and an
/// optional suggestion. In `--json` mode it is printed as `{"success": false, "error": {...}}`.
public struct RemindersError: Error, Hashable, Sendable, Codable, CustomStringConvertible {
  /// Machine-readable error codes. Scripts can rely on these values.
  public enum Code: String, CaseIterable, Hashable, Sendable, Codable {
    case permissionDenied = "PERMISSION_DENIED"
    case listNotFound = "LIST_NOT_FOUND"
    case reminderNotFound = "REMINDER_NOT_FOUND"
    case sectionNotFound = "SECTION_NOT_FOUND"
    case ambiguousReminder = "AMBIGUOUS_REMINDER"
    case reminderKitUnavailable = "REMINDERKIT_UNAVAILABLE"
    case databaseNotFound = "DB_NOT_FOUND"
    case syncTriggerFailed = "SYNC_TRIGGER_FAILED"
    case invalidArgument = "INVALID_ARGUMENT"
    /// One or more `doctor` checks failed.
    case checksFailed = "CHECKS_FAILED"
    /// The Reminders store refused an operation (a failed save or removal).
    case storeFailure = "STORE_FAILURE"
    /// Reminders changed the data while it was being edited, again after retrying.
    case storeConflict = "STORE_CONFLICT"
    /// Apple Reminders isn't available on this platform (any OS other than macOS).
    case unsupportedPlatform = "UNSUPPORTED_PLATFORM"
    /// A client's configuration file can't be read as JSON, or isn't shaped as expected; it was left alone.
    case configInvalid = "CONFIG_INVALID"
    /// The client already has a different `reminders` server; `--force` replaces it.
    case configConflict = "CONFIG_CONFLICT"
    /// Writing a configuration file, or a client's own setup command, failed.
    case setupFailed = "SETUP_FAILED"
    /// The command exists but isn't implemented yet.
    case notImplemented = "NOT_IMPLEMENTED"
    case unknown = "UNKNOWN"
  }

  public var code: Code
  public var message: String
  public var suggestion: String?

  public init(_ code: Code, _ message: String, suggestion: String? = nil) {
    self.code = code
    self.message = message
    self.suggestion = suggestion
  }

  public var description: String { message }
}

extension RemindersError {
  /// Section memberships changed between reading and writing them.
  public static let membershipConflict = RemindersError(
    .storeConflict, "Reminders changed this list's sections while they were being edited", suggestion: "Try again")

  /// A command or option that exists in the CLI but isn't implemented yet.
  public static func notImplemented(_ feature: String) -> RemindersError {
    RemindersError(
      .notImplemented, "\(feature) is not implemented yet", suggestion: "Track progress at \(ProductInfo.homepage)")
  }

  /// Apple Reminders doesn't exist on this platform.
  public static let unsupportedPlatform = RemindersError(
    .unsupportedPlatform, "Apple Reminders is only available on macOS",
    suggestion: "Run \(ProductInfo.name) on a Mac with macOS 26 or later")

  /// Any error as a ``RemindersError``; errors of other types become ``Code/unknown``.
  public init(wrapping error: any Error) {
    if let error = error as? RemindersError {
      self = error
    } else {
      self.init(.unknown, String(describing: error))
    }
  }
}
