// Ported from remi src/core/fuzzy.ts (MIT, Matthew O'Riordan).
//
// Fuzzy matching for list and section names. Makes the CLI forgiving: users don't need exact names.
// Matching priority: exact > case-insensitive exact > substring > no match.
// If multiple substring matches, all are reported so the caller can ask the user.

/// Find the best match for `query` among `items`.
/// Returns the single best match, or throws a ``RemiCommandError`` with suggestions if ambiguous or missing.
public func fuzzyFind<T>(
  _ query: String, in items: [T], name getName: (T) -> String, itemType: String
) throws(RemiCommandError) -> T {
  if items.isEmpty {
    throw RemiCommandError(.listNotFound, "No \(itemType)s found")
  }

  let q = query.jsLowercased

  // 1. Exact match
  if let exact = items.first(where: { getName($0).jsEquals(query) }) { return exact }

  // 2. Case-insensitive exact match
  if let ciExact = items.first(where: { getName($0).jsLowercased.jsEquals(q) }) { return ciExact }

  // 3. Substring match (case-insensitive)
  let substringMatches = items.filter { getName($0).jsLowercased.jsIncludes(q) }

  if substringMatches.count == 1 { return substringMatches[0] }

  if substringMatches.count > 1 {
    let names = substringMatches.map { "  - \(getName($0))" }.joined(separator: "\n")
    throw RemiCommandError(
      .ambiguousReminder, "\"\(query)\" matches multiple \(itemType)s:\n\(names)",
      suggestion: "Be more specific, or use the full name")
  }

  // 4. No match: suggest everything available
  let allNames = items.map { "  - \(getName($0))" }.joined(separator: "\n")
  throw RemiCommandError(
    .listNotFound, "No \(itemType) matching \"\(query)\"", suggestion: "Available \(itemType)s:\n\(allNames)")
}
