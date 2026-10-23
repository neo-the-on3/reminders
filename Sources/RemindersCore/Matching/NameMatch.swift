/// Result of looking up something by a name the user typed.
public enum NameMatch<Element> {
  /// One best candidate.
  case unique(Element)
  /// Several candidates match equally well, in their original order.
  case ambiguous([Element])
  case none
}

extension Collection {
  /// Forgiving name lookup, so users don't need exact names. In order of preference: an exact match, a
  /// case-insensitive exact match, then a case-insensitive substring match (ambiguous when several contain it).
  public func match(_ query: String, by name: (Element) -> String) -> NameMatch<Element> {
    if let exact = first(where: { name($0) == query }) { return .unique(exact) }
    let folded = query.lowercased()
    if let exact = first(where: { name($0).lowercased() == folded }) { return .unique(exact) }
    let containing = filter { name($0).lowercased().contains(folded) }
    switch containing.count {
    case 0: return .none
    case 1: return .unique(containing[0])
    default: return .ambiguous(containing)
    }
  }
}

extension Collection where Element == ReminderList {
  /// The list the user means by `query`.
  public func resolve(_ query: String) throws(RemindersError) -> ReminderList {
    try resolveNamed(query, kind: "list", notFound: .listNotFound, name: \.title)
  }
}

extension Collection where Element == Section {
  /// The section the user means by `query`.
  public func resolve(_ query: String) throws(RemindersError) -> Section {
    try resolveNamed(query, kind: "section", notFound: .sectionNotFound, name: \.displayName)
  }
}

extension Collection {
  fileprivate func resolveNamed(
    _ query: String, kind: String, notFound: RemindersError.Code, name: (Element) -> String
  ) throws(RemindersError) -> Element {
    guard !isEmpty else { throw RemindersError(notFound, "No \(kind)s found") }
    func bullets(_ items: [Element]) -> String { items.map { "  - \(name($0))" }.joined(separator: "\n") }
    switch match(query, by: name) {
    case .unique(let item):
      return item
    case .ambiguous(let candidates):
      throw RemindersError(
        .ambiguousReminder, "\"\(query)\" matches multiple \(kind)s:\n\(bullets(candidates))",
        suggestion: "Be more specific, or use the full name")
    case .none:
      throw RemindersError(
        notFound, "No \(kind) matching \"\(query)\"", suggestion: "Available \(kind)s:\n\(bullets(Array(self)))")
    }
  }
}

extension Collection where Element == Reminder {
  /// The reminder in `list` the user means: the first whose identifier starts with `idPrefix` (case-insensitive)
  /// when one is given, otherwise the best title match for `title`.
  public func find(title: String, idPrefix: String? = nil, inList list: String) throws(RemindersError) -> Reminder {
    if let idPrefix, !idPrefix.isEmpty {
      let prefix = idPrefix.uppercased()
      guard let reminder = first(where: { $0.id.uppercased().hasPrefix(prefix) }) else {
        throw RemindersError(
          .reminderNotFound, "No reminder found with ID starting with \"\(idPrefix)\" in \"\(list)\"")
      }
      return reminder
    }
    switch match(title, by: \.title) {
    case .unique(let reminder):
      return reminder
    case .ambiguous(let candidates):
      let names = candidates.map { "  - \"\($0.title)\"" }.joined(separator: "\n")
      throw RemindersError(
        .ambiguousReminder, "\"\(title)\" matches multiple reminders in \"\(list)\":\n\(names)",
        suggestion: "Be more specific, or use --id <prefix>")
    case .none:
      throw RemindersError(
        .reminderNotFound, "No reminder matching \"\(title)\" in \"\(list)\"",
        suggestion: "Use \"\(ProductInfo.name) list '\(list)'\" to see available reminders")
    }
  }
}
