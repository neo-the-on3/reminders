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
}
