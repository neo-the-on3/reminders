import Foundation

/// Paths as the file system resolves them, so everything the setup commands print and write uses one form.
public enum PhysicalPath {
  /// The absolute `path` with `.`, `..` and every symlink resolved, the way `realpath(3)` does: on macOS `/tmp/x`
  /// is `/private/tmp/x`. Components that don't exist yet are kept as they are, after the deepest one that does.
  ///
  /// A symlink whose target doesn't exist yet (a dangling link) is followed too, so writing to the result creates
  /// the target rather than replacing the link.
  public static func of(_ path: String) -> String {
    of(path, hops: 0)
  }

  private static func of(_ path: String, hops: Int) -> String {
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
      // Up to 32 links, as the system allows, so a loop of them ends.
      if hops < 32, let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: head) {
        let target =
          destination.hasPrefix("/") ? destination : url.deletingLastPathComponent().appending(path: destination).path
        return of(([target] + missing.reversed()).joined(separator: "/"), hops: hops + 1)
      }
      let parent = url.deletingLastPathComponent().path
      guard parent != head, !parent.isEmpty else { return path }
      missing.append(url.lastPathComponent)
      head = parent
    }
  }
}
