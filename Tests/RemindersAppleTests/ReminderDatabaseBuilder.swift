import CSQLite
import Foundation
import RemindersCore

/// Builds Reminders-shaped SQLite databases in a temporary directory, with just the tables and columns the section
/// reader uses (the documented schema; `scripts/capture-section-fixtures.sh` dumps the real one on a Mac).
final class ReminderDatabaseBuilder {
  let directory: URL

  init() throws {
    directory = FileManager.default.temporaryDirectory.appending(path: "reminders-db-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }

  static let schema = """
    CREATE TABLE ZREMCDBASELIST (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, ZMARKEDFORDELETION INTEGER, \
    ZIDENTIFIER BLOB, ZNAME VARCHAR, ZMEMBERSHIPSOFREMINDERSINSECTIONSASDATA BLOB, \
    ZMEMBERSHIPSOFREMINDERSINSECTIONSCHECKSUM VARCHAR, ZRESOLUTIONTOKENMAP_V3_JSONDATA BLOB);
    CREATE TABLE ZREMCDBASESECTION (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, ZMARKEDFORDELETION INTEGER, \
    ZLIST INTEGER, ZIDENTIFIER BLOB, ZDISPLAYNAME VARCHAR, ZCREATIONDATE TIMESTAMP);
    CREATE TABLE ZREMCDREMINDER (Z_PK INTEGER PRIMARY KEY, ZMARKEDFORDELETION INTEGER, ZCOMPLETED INTEGER, \
    ZLIST INTEGER, ZIDENTIFIER BLOB, ZTITLE VARCHAR);
    """

  /// Creates `Data-<name>.sqlite` from `sql` (run after the schema unless `schema` is false) and returns its path.
  @discardableResult
  func database(_ name: String, schema: Bool = true, _ sql: String) throws -> String {
    let path = directory.appending(path: "Data-\(name).sqlite").path
    var handle: OpaquePointer?
    guard sqlite3_open(path, &handle) == SQLITE_OK else { throw BuilderError(message: "open \(path)") }
    defer { sqlite3_close(handle) }
    var message: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(handle, (schema ? Self.schema : "") + sql, nil, nil, &message) == SQLITE_OK else {
      defer { sqlite3_free(message) }
      throw BuilderError(message: message.map { String(cString: $0) } ?? "exec failed")
    }
    return path
  }

  /// `X'…'`: a UUID string as the 16-byte blob Reminders stores.
  static func blob(_ uuid: String) -> String {
    "X'\(uuid.replacingOccurrences(of: "-", with: ""))'"
  }

  /// `X'…'`: text stored as a blob, the way Core Data stores JSON.
  static func blob(utf8 text: String) -> String {
    "X'\(text.utf8.map { String(format: "%02X", $0) }.joined())'"
  }

  /// `'…'` with quotes doubled.
  static func text(_ text: String) -> String {
    "'\(text.replacingOccurrences(of: "'", with: "''"))'"
  }
}

struct BuilderError: Error {
  var message: String
}

/// A machine whose Reminders databases are the given files, or which has no Full Disk Access.
struct DatabaseProbe: SystemProbe {
  var files: [String]
  var fullDiskAccess = true

  var operatingSystemVersion: String? { "26.0" }
  var embeddedInfoPlist: [String: String]? { nil }
  var remindersDataDirectory: String { "/Stores" }
  func remindersDataDirectoryExists() -> Bool { true }
  func remindersDatabaseFiles() throws(RemindersError) -> [String] {
    guard fullDiskAccess else {
      throw RemindersError(.permissionDenied, "Cannot access Reminders database — permission denied")
    }
    return files
  }
  var hostApplication: HostApplication? { nil }
  func openSettings(_ pane: SettingsPane) -> Bool { false }
}
