import CSQLite
import RemindersCore

/// A read-only connection to an SQLite database, just enough to read rows.
///
/// The database is opened with `SQLITE_OPEN_READONLY`, so nothing this type does can change it. A busy timeout
/// rides out Reminders' own writes.
final class SQLiteDatabase {
  /// One column value of a result row.
  enum Value: Hashable {
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob([UInt8])
    case null

    var integer: Int64? {
      if case .integer(let value) = self { value } else { nil }
    }

    /// Text, or a blob's bytes as UTF-8 (Core Data stores JSON as blobs).
    var string: String? {
      switch self {
      case .text(let text): text
      case .blob(let bytes): String(validating: bytes, as: UTF8.self)
      default: nil
      }
    }

    var bytes: [UInt8]? {
      switch self {
      case .blob(let bytes): bytes
      case .text(let text): Array(text.utf8)
      default: nil
      }
    }
  }

  let path: String
  private let handle: OpaquePointer

  init(readOnlyAt path: String, busyTimeout milliseconds: Int32 = 5_000) throws(RemindersError) {
    var handle: OpaquePointer?
    let status = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
    guard status == SQLITE_OK, let handle else {
      let reason = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "status \(status)"
      sqlite3_close(handle)
      throw Self.failure(path, reason, status: status)
    }
    self.path = path
    self.handle = handle
    sqlite3_busy_timeout(handle, milliseconds)
  }

  deinit {
    sqlite3_close_v2(handle)
  }

  /// Runs one statement with `?` parameters bound in order and returns every row.
  func rows(_ sql: String, _ parameters: Value...) throws(RemindersError) -> [[Value]] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw error(sqlite3_errcode(handle))
    }
    defer { sqlite3_finalize(statement) }
    for (index, parameter) in parameters.enumerated() {
      try bind(parameter, at: Int32(index + 1), in: statement)
    }
    var rows: [[Value]] = []
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return rows }
      guard status == SQLITE_ROW else { throw error(status) }
      rows.append((0..<sqlite3_column_count(statement)).map { column($0, of: statement) })
    }
  }

  private func bind(_ value: Value, at index: Int32, in statement: OpaquePointer) throws(RemindersError) {
    // SQLITE_TRANSIENT: SQLite copies the bytes before this call returns.
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    let status: Int32 =
      switch value {
      case .integer(let integer): sqlite3_bind_int64(statement, index, integer)
      case .real(let real): sqlite3_bind_double(statement, index, real)
      case .text(let text): sqlite3_bind_text(statement, index, text, -1, transient)
      case .blob(let bytes):
        bytes.withUnsafeBytes {
          sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), transient)
        }
      case .null: sqlite3_bind_null(statement, index)
      }
    guard status == SQLITE_OK else { throw error(status) }
  }

  private func column(_ index: Int32, of statement: OpaquePointer) -> Value {
    switch sqlite3_column_type(statement, index) {
    case SQLITE_INTEGER:
      return .integer(sqlite3_column_int64(statement, index))
    case SQLITE_FLOAT:
      return .real(sqlite3_column_double(statement, index))
    case SQLITE_TEXT:
      guard let text = sqlite3_column_text(statement, index) else { return .null }
      return .text(String(cString: text))
    case SQLITE_BLOB:
      let count = Int(sqlite3_column_bytes(statement, index))
      guard count > 0, let bytes = sqlite3_column_blob(statement, index) else { return .blob([]) }
      return .blob(Array(UnsafeRawBufferPointer(start: bytes, count: count)))
    default:
      return .null
    }
  }

  private func error(_ status: Int32) -> RemindersError {
    Self.failure(path, String(cString: sqlite3_errmsg(handle)), status: status)
  }

  private static func failure(_ path: String, _ reason: String, status: Int32) -> RemindersError {
    let denied = status == SQLITE_AUTH || status == SQLITE_PERM || status == SQLITE_CANTOPEN
    return RemindersError(
      denied ? .permissionDenied : .storeFailure, "Cannot read the Reminders database (\(reason))",
      suggestion: denied ? nil : "Reminders may be busy syncing; try again")
  }
}
