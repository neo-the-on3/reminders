import Foundation

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

  /// The list's live sections, numbered from 0, in the order the user arranged them in Reminders.
  ///
  /// - Parameter ordering: The list's `ZSECTIONIDSORDERINGASDATA`. Sections are ordered as in its
  ///   `orderedIdentifiers`; sections it doesn't name follow in creation order (by `Z_PK`), and identifiers of
  ///   sections that no longer exist are skipped. Without it, or when it can't be read, all sections are in
  ///   creation order.
  public static func sections(
    _ rows: some Collection<Section>, inList listName: String, ordering: [UInt8]? = nil
  ) -> [RemindersCore.Section] {
    let live = rows.filter { !$0.isMarkedForDeletion && $0.identifier != nil && $0.displayName != nil }
    let byCreation = live.sorted { $0.key < $1.key }
    let arranged = self.arranged(byCreation, by: sectionOrder(ordering)) { $0.identifier ?? "" }
    return arranged.enumerated().map { order, row in
      RemindersCore.Section(
        id: row.identifier ?? "", displayName: row.displayName ?? "", listName: listName, sortOrder: order)
    }
  }

  /// `items` in the order of `orderedIdentifiers` (compared case-insensitively); items it doesn't name follow in
  /// their current order, and identifiers it names that aren't among the items are skipped.
  public static func arranged<Item>(
    _ items: [Item], by orderedIdentifiers: [String], identifier: (Item) -> String
  ) -> [Item] {
    let positions = Dictionary(
      orderedIdentifiers.enumerated().map { ($0.element.uppercased(), $0.offset) },
      uniquingKeysWith: { first, _ in first })
    func rank(_ item: (offset: Int, element: Item)) -> (Int, Int) {
      (positions[identifier(item.element).uppercased()] ?? positions.count + item.offset, item.offset)
    }
    return items.enumerated().sorted { rank($0) < rank($1) }.map(\.element)
  }

  /// The section identifiers in a list's `ZSECTIONIDSORDERINGASDATA` JSON, in order; empty when there's none or
  /// it can't be read.
  public static func sectionOrder(_ ordering: [UInt8]?) -> [String] {
    struct Ordering: Decodable { var orderedIdentifiers: [String] }
    guard let ordering, !ordering.isEmpty else { return [] }
    return (try? JSONDecoder().decode(Ordering.self, from: Data(ordering)))?.orderedIdentifiers ?? []
  }
}
