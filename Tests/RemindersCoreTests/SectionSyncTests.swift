import Foundation
import Testing

@testable import RemindersCore

@Suite("Section memberships")
struct SectionMembershipsTests {
  @Test("a list without membership data has no entries")
  func empty() throws {
    for stored in [nil, "", "   "] as [String?] {
      #expect(try SectionMemberships(storedData: stored).entries.isEmpty)
    }
  }

  @Test("entries are read with their times; unknown fields are ignored")
  func entries() throws {
    let memberships = try SectionMemberships(
      storedData:
        #"{"memberships":[{"modifiedOn":783456789.12345678,"groupID":"G1","memberID":"M1"},{"memberID":"M2","groupID":"G1","extra":true}],"minimumSupportedVersion":20230430,"future":1}"#
    )
    #expect(
      memberships.entries == [
        .init(reminderID: "M1", sectionID: "G1", modifiedOn: 783_456_789.123_456_78),
        .init(reminderID: "M2", sectionID: "G1"),
      ])
    #expect(memberships.section(of: "M2") == "G1")
    #expect(memberships.section(of: "M9") == nil)
  }

  @Test("a reminder listed more than once is in the section it was put in last")
  func newestWins() throws {
    let memberships = SectionMemberships(entries: [
      .init(reminderID: "M1", sectionID: "G2", modifiedOn: 9),
      .init(reminderID: "M1", sectionID: "G1", modifiedOn: 5),
      .init(reminderID: "M2", sectionID: "G1", modifiedOn: 5),
      .init(reminderID: "M2", sectionID: "G3", modifiedOn: 5),
    ])
    #expect(memberships.section(of: "M1") == "G2")
    #expect(memberships.section(of: "M2") == "G3")
  }

  @Test("corrupt data is reported, never overwritten")
  func corrupt() {
    #expect(throws: RemindersError.self) { try SectionMemberships(storedData: "{oops") }
    #expect(throws: RemindersError.self) { try SectionMemberships(storedData: "[1]") }
  }

  @Test("Core Data identifiers convert to UUIDs")
  func uuid() {
    #expect(UUID(compactHex: "0123456789abcdef0123456789abcdef")?.uuidString == "01234567-89AB-CDEF-0123-456789ABCDEF")
    #expect(UUID(compactHex: "0123") == nil)
  }
}

@Suite("Persisted JSON")
struct PersistedJSONTests {
  @Test("round-trips compactly, keeping key order, unknown fields and escapes")
  func roundTrip() throws {
    let text = #"{"b":1,"a":[true,false,null],"s":"line\nbreak \"q\" \\ \u0001 é/😀","n":-0.5}"#
    #expect(
      try PersistedJSON(parsing: text).serialized
        == #"{"b":1,"a":[true,false,null],"s":"line\nbreak \"q\" \\ \u0001 é/😀","n":-0.5}"#)
  }

  @Test("prints integral numbers without a fraction and uses exponents only for extreme magnitudes")
  func numbers() {
    let cases: [(Double, String)] = [
      (20_230_430, "20230430"), (783_456_789.123456, "783456789.123456"), (0.000001, "0.000001"), (1e-7, "1e-7"),
      (1e21, "1e+21"), (123e18, "123000000000000000000"), (-0.0, "0"), (1.5, "1.5"),
    ]
    for (value, text) in cases {
      #expect(PersistedJSON.format(value) == text)
    }
  }

  @Test("rejects what strict JSON rejects")
  func strictness() {
    for text in ["", "{", "[1,]", "{\"a\":01}", "'x'", "{\"a\":1} x", "\"\\x\""] {
      #expect(throws: JSONParseError.self) { try PersistedJSON(parsing: text) }
    }
  }
}

@Suite("Section order and membership data from objects")
struct SectionObjectsTests {
  @Test("items follow the given identifiers, case-insensitively; the rest keep their order after them")
  func arranged() {
    let arranged = SectionOrdering.arranged(["a", "B", "c", "d"], by: ["D", "x", "b"]) { $0 }
    #expect(arranged == ["d", "B", "a", "c"])
    #expect(SectionOrdering.arranged(["a", "b"], by: []) { $0 } == ["a", "b"])
  }

  @Test("stored ordering JSON gives its identifiers in order; anything unreadable gives none")
  func storedOrdering() {
    // The Port Test list's ordering as captured on macOS 27.0.1 after Gamma was dragged above Alpha.
    let captured =
      #"{"orderedIdentifiers":["EB33B981-786B-420F-8E73-70512A532667","ABCECB2F-5CED-4351-8028-5CE6774B6C9B","#
      + #""CE743022-A15F-4347-AA00-877C21C65423"],"minimumSupportedVersion":20230430}"#
    #expect(
      SectionOrdering.identifiers(Array(captured.utf8)) == [
        "EB33B981-786B-420F-8E73-70512A532667", "ABCECB2F-5CED-4351-8028-5CE6774B6C9B",
        "CE743022-A15F-4347-AA00-877C21C65423",
      ])
    #expect(SectionOrdering.identifiers(nil).isEmpty)
    #expect(SectionOrdering.identifiers([]).isEmpty)
    #expect(SectionOrdering.identifiers(Array("not json".utf8)).isEmpty)
    #expect(SectionOrdering.identifiers(Array(#"{"orderedIdentifiers":"Gamma"}"#.utf8)).isEmpty)
  }

  @Test("memberships handed over as objects become data in Reminders' format that reads back the same")
  func encoded() throws {
    let entries: [SectionMemberships.Entry] = [
      .init(reminderID: "M1", sectionID: "G1", modifiedOn: 783_456_789.5), .init(reminderID: "M2", sectionID: "G2"),
    ]
    let stored = StoredMemberships(entries: entries)
    #expect(
      stored.data
        == #"{"memberships":[{"groupID":"G1","memberID":"M1","modifiedOn":783456789.5},{"groupID":"G2","memberID":"M2"}],"minimumSupportedVersion":20230430}"#
    )
    #expect(try SectionMemberships(storedData: stored.data).entries == entries)
  }
}

@Suite("Current memberships")
struct CurrentMembershipsTests {
  @Test("one entry per reminder, the newest, in the order reminders first appear")
  func current() {
    let memberships = SectionMemberships(entries: [
      .init(reminderID: "M1", sectionID: "G1", modifiedOn: 5), .init(reminderID: "M2", sectionID: "G1", modifiedOn: 5),
      .init(reminderID: "M1", sectionID: "G2", modifiedOn: 9), .init(reminderID: "M2", sectionID: "G3", modifiedOn: 1),
    ])
    #expect(
      memberships.current == [
        .init(reminderID: "M1", sectionID: "G2", modifiedOn: 9),
        .init(reminderID: "M2", sectionID: "G1", modifiedOn: 5),
      ])
    #expect(memberships.sectionsByReminder == ["M1": "G2", "M2": "G1"])
  }
}
