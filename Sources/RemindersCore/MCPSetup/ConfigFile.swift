import Foundation

/// Reading and replacing a client's config file safely.
///
/// A replacement is written atomically (to a temporary file that is then renamed over the original), after the
/// original is copied to `<file>.bak-<timestamp>`. A symlinked config (a dotfiles checkout, say) is written through
/// the link, and the original's permissions are kept.
public enum ConfigFile {
  /// The file's text, or nil when it doesn't exist.
  public static func read(_ path: String) throws(RemindersError) -> String? {
    let url = URL(filePath: PhysicalPath.of(path))
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    guard let data = FileManager.default.contents(atPath: url.path) else {
      throw RemindersError(.setupFailed, "Cannot read \(path)", suggestion: "Check the file's permissions")
    }
    guard let text = String(bytes: data, encoding: .utf8) else {
      throw RemindersError(
        .configInvalid, "\(path) isn't UTF-8 text", suggestion: "Check the file, or move it aside, then run this again")
    }
    return text
  }

  /// Replaces the file at `path` with `text`, creating it and its directory when missing. Returns the backup's
  /// path, or nil when there was no file to back up.
  @discardableResult
  public static func write(_ text: String, to path: String, now: Date = .now) throws(RemindersError) -> String? {
    let url = URL(filePath: PhysicalPath.of(path))
    let manager = FileManager.default
    do {
      try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      var backup: String?
      var permissions: Any?
      if manager.fileExists(atPath: url.path) {
        permissions = try manager.attributesOfItem(atPath: url.path)[.posixPermissions]
        let path = backupPath(for: url.path, at: now, exists: manager.fileExists(atPath:))
        try manager.copyItem(atPath: url.path, toPath: path)
        backup = path
      }
      try Data(text.utf8).write(to: url, options: .atomic)
      if let permissions { try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path) }
      return backup
    } catch {
      throw RemindersError(
        .setupFailed, "Cannot write \(path): \(error.localizedDescription)",
        suggestion: "Check that the folder is writable; the original file is unchanged")
    }
  }

  /// `<path>.bak-YYYYMMDD-HHMMSS` in `timeZone`, with `-2`, `-3`, … when that exists already.
  static func backupPath(
    for path: String, at date: Date, timeZone: TimeZone = .current, exists: (String) -> Bool
  ) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let base = "\(path).bak-\(formatter.string(from: date))"
    var candidate = base
    var counter = 2
    while exists(candidate) {
      candidate = "\(base)-\(counter)"
      counter += 1
    }
    return candidate
  }
}
