// JSONValue must reproduce JSON.parse / JSON.stringify exactly (expected values captured from Node.js).

import Testing

@testable import RemiCore

@Suite("JSONValue")
struct JSONTests {
  static let numbers: [(Double, String)] = [
    (0, "0"), (-0.0, "0"), (1, "1"), (-1, "-1"), (1.5, "1.5"), (0.1, "0.1"), (0.000001, "0.000001"),
    (0.0000001, "1e-7"), (1e21, "1e+21"), (1e20, "100000000000000000000"),
    (Double("123456789012345680000")!, "123456789012345680000"), (783_456_789.123456, "783456789.123456"),
    (Double.leastNonzeroMagnitude, "5e-324"), (1.7976931348623157e308, "1.7976931348623157e+308"), (-2.5e-7, "-2.5e-7"),
    (100, "100"),
    (20_230_430, "20230430"), (733_456_789.5, "733456789.5"), (0.1 + 0.2, "0.30000000000000004"),
  ]

  @Test("formats numbers like ECMAScript Number::toString")
  func numberFormatting() {
    for (value, expected) in Self.numbers {
      #expect(JSONValue.formatNumber(value) == expected, "\(value)")
    }
    #expect(JSONValue.number(.nan).stringified() == "null")
    #expect(JSONValue.number(.infinity).stringified() == "null")
  }

  @Test("escapes strings like JSON.stringify")
  func stringEscaping() {
    let value = JSONValue.object([("s", .string("a\"b\\c\n\t\u{01}\u{1F}\u{7F} é 😀 \u{2028}/"))])
    #expect(value.stringified() == "{\"s\":\"a\\\"b\\\\c\\n\\t\\u0001\\u001f\u{7F} é 😀 \u{2028}/\"}")
  }

  @Test("pretty prints like JSON.stringify(value, null, 2)")
  func prettyPrint() throws {
    let value = try JSONValue.parse(#"{"a":[],"b":{},"c":[1,{"d":null}],"e":"x"}"#)
    #expect(
      value.stringified(indent: 2)
        == "{\n  \"a\": [],\n  \"b\": {},\n  \"c\": [\n    1,\n    {\n      \"d\": null\n    }\n  ],\n  \"e\": \"x\"\n}"
    )
  }

  @Test("round-trips membership blobs byte for byte")
  func roundTrip() throws {
    let blob =
      #"{"minimumSupportedVersion":20230430,"memberships":[{"memberID":"A","groupID":"B","modifiedOn":783456789.123456}]}"#
    #expect(try JSONValue.parse(blob).stringified() == blob)
    // Whitespace is normalised exactly as JSON.stringify(JSON.parse(x)) would
    #expect(
      try JSONValue.parse(" { \"a\" : [ 1 , 2.50 ] , \"b\" : true } ").stringified() == #"{"a":[1,2.5],"b":true}"#)
  }

  @Test("duplicate keys keep first position and last value")
  func duplicateKeys() throws {
    #expect(try JSONValue.parse(#"{"b":1,"a":2,"b":3}"#).stringified() == #"{"b":3,"a":2}"#)
  }

  @Test("decodes escapes including surrogate pairs")
  func escapes() throws {
    #expect(try JSONValue.parse(#""\u00e9\ud83d\ude00\n\/""#) == .string("é😀\n/"))
  }

  @Test(
    "rejects what JSON.parse rejects",
    arguments: ["", "{", "[1,]", "{\"a\":1,}", "01", "1.", ".5", "'x'", "nul", "1 2", "\"\t\"", "{a:1}", "+1"])
  func rejects(_ text: String) {
    #expect(throws: JSONParseError.self) { try JSONValue.parse(text) }
  }

  @Test("subscript get/set keeps key order")
  func subscripts() {
    var value = JSONValue.object([("a", .number(1)), ("b", .number(2))])
    value["a"] = .number(3)
    value["c"] = .bool(true)
    value["b"] = nil
    #expect(value.stringified() == #"{"a":3,"c":true}"#)
    #expect(value.keys == ["a", "c"])
  }

  @Test("sortingKeys sorts recursively")
  func sorting() throws {
    #expect(
      try JSONValue.parse(#"{"b":{"y":1,"x":2},"a":[{"d":1,"c":2}]}"#).sortingKeys.stringified()
        == #"{"a":[{"c":2,"d":1}],"b":{"x":2,"y":1}}"#)
  }

  @Test("encodes domain types with TypeScript key order, omitting nil fields")
  func domainTypes() {
    let reminder = Reminder(
      id: "1", title: "T", listID: "L", listName: "List", priority: .low, notes: "n", flagged: false)
    #expect(
      reminder.jsonValue.stringified()
        == #"{"id":"1","title":"T","isCompleted":false,"listID":"L","listName":"List","priority":"low","notes":"n","flagged":false}"#
    )
    #expect(
      ReminderList(id: "x", title: "Y", reminderCount: 2, overdueCount: 0).jsonValue.stringified()
        == #"{"id":"x","title":"Y","reminderCount":2,"overdueCount":0}"#)
    #expect(
      Section(id: "s", displayName: "D", listName: "L", sortOrder: 3).jsonValue.stringified()
        == #"{"id":"s","displayName":"D","listName":"L","sortOrder":3}"#)
    #expect(
      RemiError(code: .listNotFound, message: "m").jsonValue.stringified()
        == #"{"code":"LIST_NOT_FOUND","message":"m"}"#)
  }
}
