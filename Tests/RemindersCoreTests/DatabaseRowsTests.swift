import Foundation
import Testing

@testable import RemindersCore

@Suite("Sections: database rows")
struct DatabaseRowsTests {
  @Test("16-byte identifiers become upper-case dashed UUIDs")
  func identifiers() {
    let bytes: [UInt8] = [
      0x2F, 0x1C, 0x9A, 0x0E, 0x5B, 0x3D, 0x4E, 0x7F, 0x8A, 0x01, 0x0B, 0xC2, 0xD3, 0xE4, 0xF5, 0x06,
    ]
    #expect(DatabaseRows.identifier(bytes) == "2F1C9A0E-5B3D-4E7F-8A01-0BC2D3E4F506")
    #expect(DatabaseRows.identifier(bytes.dropLast()) == nil)
    #expect(DatabaseRows.identifier([UInt8]()) == nil)
  }

  @Test("a list is found by identifier, otherwise by a unique exact name")
  func lists() {
    let rows = [
      DatabaseRows.List(key: 1, identifier: "AAAA", name: "Groceries"),
      DatabaseRows.List(key: 2, identifier: "BBBB", name: "Work"),
      DatabaseRows.List(key: 3, identifier: "CCCC", name: "Work"),
    ]
    #expect(DatabaseRows.row(for: ReminderList(id: "bbbb", title: "Renamed"), in: rows)?.key == 2)
    #expect(DatabaseRows.row(for: ReminderList(id: "x", title: "Groceries"), in: rows)?.key == 1)
    #expect(DatabaseRows.row(for: ReminderList(id: "x", title: "Work"), in: rows) == nil)
    #expect(DatabaseRows.row(for: ReminderList(id: "x", title: "groceries"), in: rows) == nil)
  }

  @Test("sections leave out deleted and incomplete rows and are ordered by creation")
  func sections() {
    let rows = [
      DatabaseRows.Section(key: 9, identifier: "C", displayName: "Bakery"),
      DatabaseRows.Section(key: 4, identifier: "A", displayName: "Dairy"),
      DatabaseRows.Section(key: 5, identifier: "B", displayName: "Gone", isMarkedForDeletion: true),
      DatabaseRows.Section(key: 6, identifier: nil, displayName: "No ID"),
      DatabaseRows.Section(key: 7, identifier: "D", displayName: "Produce"),
    ]
    let sections = DatabaseRows.sections(rows, inList: "Groceries")
    #expect(sections.map(\.displayName) == ["Dairy", "Produce", "Bakery"])
    #expect(sections.map(\.sortOrder) == [0, 1, 2])
    #expect(sections.allSatisfy { $0.listName == "Groceries" })
  }

  /// The Port Test list as captured on macOS 27.0.1 after Gamma was dragged above Alpha in Reminders.
  private static let alpha = DatabaseRows.Section(
    key: 6, identifier: "ABCECB2F-5CED-4351-8028-5CE6774B6C9B", displayName: "Alpha")
  private static let beta = DatabaseRows.Section(
    key: 7, identifier: "CE743022-A15F-4347-AA00-877C21C65423", displayName: "Beta")
  private static let gamma = DatabaseRows.Section(
    key: 8, identifier: "EB33B981-786B-420F-8E73-70512A532667", displayName: "Gamma")
  /// ZSECTIONIDSORDERINGASDATA, the exact stored bytes (hex from the capture).
  static let capturedOrdering = Array(
    Data(
      hexString:
        "7B226F7264657265644964656E74696669657273223A5B2245423333423938312D373836422D343230462D384537332D"
        + "373035313241353332363637222C2241424345434232462D354345442D343335312D383032382D354345363737344236"
        + "433942222C2243453734333032322D413135462D343334372D414130302D383737433231433635343233225D2C226D69"
        + "6E696D756D537570706F7274656456657273696F6E223A32303233303433307D")!)

  private static func names(_ ordering: [UInt8]?) -> [String] {
    DatabaseRows.sections([alpha, beta, gamma], inList: "Port", ordering: ordering).map(\.displayName)
  }

  @Test("sections follow the order the user arranged in Reminders, numbered in that order")
  func arrangedOrder() {
    let sections = DatabaseRows.sections(
      [Self.alpha, Self.beta, Self.gamma], inList: "Port", ordering: Self.capturedOrdering)
    #expect(sections.map(\.displayName) == ["Gamma", "Alpha", "Beta"])
    #expect(sections.map(\.sortOrder) == [0, 1, 2])
  }

  @Test("identifiers match in any case; unnamed sections follow in creation order; unknown ones are skipped")
  func partialOrder() {
    let lower = [Self.gamma, Self.alpha].map { "\"\($0.identifier!.lowercased())\"" }.joined(separator: ",")
    #expect(Self.names(Array(#"{"orderedIdentifiers":[\#(lower)]}"#.utf8)) == ["Gamma", "Alpha", "Beta"])
    let partial = #"{"orderedIdentifiers":["0D5E8F4A-1B2C-4D3E-9F5A-6B7C8D9E0F1A","\#(Self.beta.identifier!)"]}"#
    #expect(Self.names(Array(partial.utf8)) == ["Beta", "Alpha", "Gamma"])
    #expect(Self.names(Array(#"{"orderedIdentifiers":[]}"#.utf8)) == ["Alpha", "Beta", "Gamma"])
  }

  @Test("without a readable order, sections are in creation order")
  func noOrder() {
    #expect(Self.names(nil) == ["Alpha", "Beta", "Gamma"])
    #expect(Self.names([]) == ["Alpha", "Beta", "Gamma"])
    #expect(Self.names(Array("not json".utf8)) == ["Alpha", "Beta", "Gamma"])
    #expect(Self.names(Array(#"{"orderedIdentifiers":"Gamma"}"#.utf8)) == ["Alpha", "Beta", "Gamma"])
  }
}

extension Data {
  /// Bytes from a string of hex digit pairs; nil when it isn't one.
  fileprivate init?(hexString: String) {
    let nibbles = hexString.compactMap(\.hexDigitValue).map(UInt8.init)
    guard nibbles.count == hexString.count, nibbles.count.isMultiple(of: 2) else { return nil }
    self.init(stride(from: 0, to: nibbles.count, by: 2).map { nibbles[$0] << 4 | nibbles[$0 + 1] })
  }
}
