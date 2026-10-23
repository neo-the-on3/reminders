/// Rows of the Reminders database that sections are read from, whatever reads them.
///
/// Reminders keeps lists in `ZREMCDBASELIST`, sections in `ZREMCDBASESECTION` and identifiers as 16-byte blobs.
/// A deleted row stays behind with `ZMARKEDFORDELETION` set until sync cleans it up.
public enum DatabaseRows {
  /// A `ZREMCDBASELIST` row.
  public struct List: Hashable, Sendable {
    /// `Z_PK`, which section rows point at.
    public var key: Int64
    /// `ZIDENTIFIER` as a dashed UUID string.
    public var identifier: String?
    public var name: String
    /// The database file the row is in; Reminders keeps one per account.
    public var database: String

    public init(key: Int64, identifier: String?, name: String, database: String = "") {
      self.key = key
      self.identifier = identifier
      self.name = name
      self.database = database
    }
  }

  /// A `ZREMCDBASESECTION` row.
  public struct Section: Hashable, Sendable {
    public var key: Int64
    public var identifier: String?
    public var displayName: String?
    public var isMarkedForDeletion: Bool

    public init(key: Int64, identifier: String?, displayName: String?, isMarkedForDeletion: Bool = false) {
      self.key = key
      self.identifier = identifier
      self.displayName = displayName
      self.isMarkedForDeletion = isMarkedForDeletion
    }
  }

  /// A 16-byte identifier blob as the upper-case dashed UUID string EventKit and the membership data use.
  public static func identifier(_ bytes: some Collection<UInt8>) -> String? {
    guard bytes.count == 16 else { return nil }
    let hex = bytes.map { byte in
      let digits = String(byte, radix: 16, uppercase: true)
      return digits.count == 1 ? "0" + digits : digits
    }.joined()
    let groups = [8, 4, 4, 4, 12].reduce(into: (parts: [Substring](), rest: Substring(hex))) { state, length in
      state.parts.append(state.rest.prefix(length))
      state.rest = state.rest.dropFirst(length)
    }
    return groups.parts.joined(separator: "-")
  }

  /// The row for an EventKit list: the one with its identifier, otherwise the only one with its exact name.
  /// Nil when there's none, or several with that name and none with the identifier.
  public static func row(for list: ReminderList, in rows: some Collection<List>) -> List? {
    if let match = rows.first(where: { $0.identifier?.caseInsensitiveCompare(list.id) == .orderedSame }) {
      return match
    }
    let named = rows.filter { $0.name == list.title }
    return named.count == 1 ? named.first : nil
  }

  /// The list's live sections in creation order (by `Z_PK`), numbered from 0.
  public static func sections(_ rows: some Collection<Section>, inList listName: String) -> [RemindersCore.Section] {
    let live = rows.filter { !$0.isMarkedForDeletion && $0.identifier != nil && $0.displayName != nil }
    return live.sorted { $0.key < $1.key }.enumerated().map { order, row in
      RemindersCore.Section(
        id: row.identifier ?? "", displayName: row.displayName ?? "", listName: listName, sortOrder: order)
    }
  }
}
