// Ported from remi src/core/lookup.ts (MIT, Matthew O'Riordan).
//
// Resolves a human-friendly title (or an ID prefix) to a reminder within a list. The Apple-side
// layer fetches the list's reminders; the matching itself is pure and lives here.

/// Pick the reminder in `reminders` (all reminders of `listName`) that matches `title`,
/// or the one whose ID starts with `id` when an ID prefix is given.
public func findReminder(
  in reminders: [Reminder], listName: String, title: String, id: String? = nil
) throws(RemiCommandError) -> Reminder {
  // If --id is provided, match by case-insensitive ID prefix
  if let id, !id.isEmpty {
    let idPrefix = id.uppercased()
    guard let match = reminders.first(where: { $0.id.uppercased().hasPrefix(idPrefix) }) else {
      throw RemiCommandError(
        .reminderNotFound, "No reminder found with ID starting with \"\(id)\" in \"\(listName)\"")
    }
    return match
  }

  let q = title.jsLowercased

  // 1. Exact match
  if let exact = reminders.first(where: { $0.title.jsEquals(title) }) { return exact }

  // 2. Case-insensitive exact match
  if let ciExact = reminders.first(where: { $0.title.jsLowercased.jsEquals(q) }) { return ciExact }

  // 3. Substring match
  let substringMatches = reminders.filter { $0.title.jsLowercased.jsIncludes(q) }
  if substringMatches.count == 1 { return substringMatches[0] }

  if substringMatches.count > 1 {
    let names = substringMatches.map { "  - \"\($0.title)\"" }.joined(separator: "\n")
    throw RemiCommandError(
      .ambiguousReminder, "\"\(title)\" matches multiple reminders in \"\(listName)\":\n\(names)",
      suggestion: "Be more specific, or use --id <prefix>")
  }

  throw RemiCommandError(
    .reminderNotFound, "No reminder matching \"\(title)\" in \"\(listName)\"",
    suggestion: "Use \"remi list '\(listName)'\" to see available reminders")
}
