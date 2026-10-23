import Foundation

/// Paths as the file system resolves them, so everything the setup commands print and write uses one form.
public enum PhysicalPath {
  /// The absolute `path` with `.`, `..` and every symlink resolved, the way `realpath(3)` does: on macOS `/tmp/x`
  /// is `/private/tmp/x`. Components that don't exist yet are kept as they are, after the deepest one that does.
  public static func of(_ path: String) -> String {
    var head = URL(filePath: path).standardized.path
    var missing: [String] = []
    while true {
      if let resolved = realpath(head, nil) {
        defer { free(resolved) }
        let base = String(cString: resolved)
        guard !missing.isEmpty else { return base }
        return (base == "/" ? "" : base) + "/" + missing.reversed().joined(separator: "/")
      }
      let url = URL(filePath: head)
      let parent = url.deletingLastPathComponent().path
      guard parent != head, !parent.isEmpty else { return path }
      missing.append(url.lastPathComponent)
      head = parent
    }
  }
}
