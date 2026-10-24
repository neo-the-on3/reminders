import Foundation

/// The order the user arranged a list's sections in.
///
/// Reminders keeps it on the list as JSON, `{"orderedIdentifiers": [...], "minimumSupportedVersion": ...}`, and
/// leaves it unset until the user first reorders.
public enum SectionOrdering {
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

  /// The section identifiers in stored ordering JSON, in order; empty when there's none or it can't be read.
  public static func identifiers(_ ordering: [UInt8]?) -> [String] {
    struct Ordering: Decodable { var orderedIdentifiers: [String] }
    guard let ordering, !ordering.isEmpty else { return [] }
    return (try? JSONDecoder().decode(Ordering.self, from: Data(ordering)))?.orderedIdentifiers ?? []
  }
}
