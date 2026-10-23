// An order-preserving JSON value with JavaScript-compatible parsing and serialisation.
//
// remi's output and its section-membership writes are produced with `JSON.stringify`, and the
// membership blob is checksummed byte-for-byte by remindd. Foundation's encoders reorder keys and
// format numbers differently, so this type reproduces `JSON.parse` / `JSON.stringify` exactly:
// insertion-ordered keys, ECMAScript number formatting, and JSON.stringify string escaping.

/// A JSON value whose objects keep their key order.
public enum JSONValue: Equatable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([(String, JSONValue)])

  public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
    switch (lhs, rhs) {
    case (.null, .null): return true
    case (.bool(let a), .bool(let b)): return a == b
    case (.number(let a), .number(let b)): return a == b
    case (.string(let a), .string(let b)): return a == b
    case (.array(let a), .array(let b)): return a == b
    case (.object(let a), .object(let b)):
      return a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
    default: return false
    }
  }

  // MARK: Accessors

  /// Value for `key` if this is an object.
  public subscript(key: String) -> JSONValue? {
    get {
      guard case .object(let fields) = self else { return nil }
      return fields.first(where: { $0.0 == key })?.1
    }
    set {
      guard case .object(var fields) = self else { return }
      if let index = fields.firstIndex(where: { $0.0 == key }) {
        if let newValue { fields[index].1 = newValue } else { fields.remove(at: index) }
      } else if let newValue {
        fields.append((key, newValue))
      }
      self = .object(fields)
    }
  }

  public var stringValue: String? {
    if case .string(let s) = self { return s }
    return nil
  }

  public var numberValue: Double? {
    if case .number(let n) = self { return n }
    return nil
  }

  public var boolValue: Bool? {
    if case .bool(let b) = self { return b }
    return nil
  }

  public var arrayValue: [JSONValue]? {
    if case .array(let a) = self { return a }
    return nil
  }

  public var objectValue: [(String, JSONValue)]? {
    if case .object(let o) = self { return o }
    return nil
  }

  /// Keys of an object, in insertion order.
  public var keys: [String] { objectValue?.map(\.0) ?? [] }
}

// MARK: - Conversion protocol

/// Types that have a canonical JSON representation (used for `--json` output).
public protocol JSONValueConvertible {
  var jsonValue: JSONValue { get }
}

extension JSONValue: JSONValueConvertible {
  public var jsonValue: JSONValue { self }
}

extension String: JSONValueConvertible {
  public var jsonValue: JSONValue { .string(self) }
}

extension Bool: JSONValueConvertible {
  public var jsonValue: JSONValue { .bool(self) }
}

extension Int: JSONValueConvertible {
  public var jsonValue: JSONValue { .number(Double(self)) }
}

extension Double: JSONValueConvertible {
  public var jsonValue: JSONValue { .number(self) }
}

extension Array: JSONValueConvertible where Element: JSONValueConvertible {
  public var jsonValue: JSONValue { .array(map(\.jsonValue)) }
}

extension Optional: JSONValueConvertible where Wrapped: JSONValueConvertible {
  public var jsonValue: JSONValue { self?.jsonValue ?? .null }
}

// MARK: - Serialisation (JSON.stringify)

extension JSONValue {
  /// Serialise like `JSON.stringify(value, null, indent)`. `indent == 0` produces compact output.
  public func stringified(indent: Int = 0) -> String {
    var out = ""
    write(into: &out, indent: String(repeating: " ", count: max(0, min(indent, 10))), current: "")
    return out
  }

  private func write(into out: inout String, indent: String, current: String) {
    switch self {
    case .null: out += "null"
    case .bool(let b): out += b ? "true" : "false"
    case .number(let n): out += n.isFinite ? JSONValue.formatNumber(n) : "null"
    case .string(let s): JSONValue.quote(s, into: &out)
    case .array(let items):
      if items.isEmpty {
        out += "[]"
        return
      }
      let inner = current + indent
      out += "["
      for (index, item) in items.enumerated() {
        if index > 0 { out += "," }
        if !indent.isEmpty { out += "\n" + inner }
        item.write(into: &out, indent: indent, current: inner)
      }
      if !indent.isEmpty { out += "\n" + current }
      out += "]"
    case .object(let fields):
      if fields.isEmpty {
        out += "{}"
        return
      }
      let inner = current + indent
      out += "{"
      for (index, (key, value)) in fields.enumerated() {
        if index > 0 { out += "," }
        if !indent.isEmpty { out += "\n" + inner }
        JSONValue.quote(key, into: &out)
        out += indent.isEmpty ? ":" : ": "
        value.write(into: &out, indent: indent, current: inner)
      }
      if !indent.isEmpty { out += "\n" + current }
      out += "}"
    }
  }

  /// Quote a string exactly as JSON.stringify does.
  static func quote(_ s: String, into out: inout String) {
    out += "\""
    for scalar in s.unicodeScalars {
      switch scalar {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\u{08}": out += "\\b"
      case "\u{0C}": out += "\\f"
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      default:
        if scalar.value < 0x20 {
          let hex = String(scalar.value, radix: 16)
          out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
        } else {
          out.unicodeScalars.append(scalar)
        }
      }
    }
    out += "\""
  }

  /// Format a finite double using ECMAScript's Number::toString algorithm.
  public static func formatNumber(_ value: Double) -> String {
    if value == 0 { return "0" }  // also covers -0
    if value < 0 { return "-" + formatNumber(-value) }

    // Swift's description yields the shortest round-tripping digits, like ECMAScript.
    // Decompose it into a digit string and the decimal exponent n where value = 0.d1d2... × 10^n.
    let description = value.description
    var mantissa = Substring(description)
    var exponent = 0
    if let e = description.firstIndex(where: { $0 == "e" || $0 == "E" }) {
      mantissa = description[..<e]
      exponent = Int(description[description.index(after: e)...]) ?? 0
    }
    var integerPart = mantissa
    var fractionPart: Substring = ""
    if let dot = mantissa.firstIndex(of: ".") {
      integerPart = mantissa[..<dot]
      fractionPart = mantissa[mantissa.index(after: dot)...]
    }
    var digits = String(integerPart) + String(fractionPart)
    var n = integerPart.count + exponent
    let leadingZeros = digits.prefix(while: { $0 == "0" }).count
    digits.removeFirst(leadingZeros)
    n -= leadingZeros
    while digits.last == "0" { digits.removeLast() }
    if digits.isEmpty { return "0" }
    let k = digits.count

    if k <= n && n <= 21 {
      return digits + String(repeating: "0", count: n - k)
    }
    if 0 < n && n <= 21 {
      let index = digits.index(digits.startIndex, offsetBy: n)
      return String(digits[..<index]) + "." + String(digits[index...])
    }
    if -6 < n && n <= 0 {
      return "0." + String(repeating: "0", count: -n) + digits
    }
    let e = n - 1
    let sign = e < 0 ? "-" : "+"
    let head = String(digits.prefix(1))
    let tail = digits.dropFirst()
    return head + (tail.isEmpty ? "" : "." + tail) + "e" + sign + String(abs(e))
  }
}

// MARK: - Parsing (JSON.parse)

/// Error thrown when text is not valid JSON.
public struct JSONParseError: Error, Equatable, Sendable, CustomStringConvertible {
  public let offset: Int
  public let reason: String
  public var description: String { "Invalid JSON at offset \(offset): \(reason)" }
}

extension JSONValue {
  /// Parse JSON text with the same acceptance rules as `JSON.parse`.
  /// Duplicate keys keep their first position and take the last value, as in JavaScript.
  public static func parse(_ text: String) throws(JSONParseError) -> JSONValue {
    var parser = JSONTextParser(bytes: Array(text.utf8))
    parser.skipWhitespace()
    let value = try parser.parseValue(depth: 0)
    parser.skipWhitespace()
    guard parser.isAtEnd else { throw parser.error("Unexpected trailing characters") }
    return value
  }
}

private struct JSONTextParser {
  let bytes: [UInt8]
  var position = 0

  var isAtEnd: Bool { position >= bytes.count }

  func error(_ reason: String) -> JSONParseError { JSONParseError(offset: position, reason: reason) }

  mutating func skipWhitespace() {
    while position < bytes.count {
      switch bytes[position] {
      case 0x20, 0x09, 0x0A, 0x0D: position += 1
      default: return
      }
    }
  }

  mutating func expect(_ literal: String) throws(JSONParseError) {
    for byte in literal.utf8 {
      guard position < bytes.count, bytes[position] == byte else { throw error("Expected \(literal)") }
      position += 1
    }
  }

  mutating func parseValue(depth: Int) throws(JSONParseError) -> JSONValue {
    guard depth < 512 else { throw error("Nesting too deep") }
    guard position < bytes.count else { throw error("Unexpected end of input") }
    switch bytes[position] {
    case UInt8(ascii: "{"): return try parseObject(depth: depth)
    case UInt8(ascii: "["): return try parseArray(depth: depth)
    case UInt8(ascii: "\""): return .string(try parseString())
    case UInt8(ascii: "t"):
      try expect("true")
      return .bool(true)
    case UInt8(ascii: "f"):
      try expect("false")
      return .bool(false)
    case UInt8(ascii: "n"):
      try expect("null")
      return .null
    case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .number(try parseNumber())
    default: throw error("Unexpected character")
    }
  }

  mutating func parseObject(depth: Int) throws(JSONParseError) -> JSONValue {
    position += 1
    var fields: [(String, JSONValue)] = []
    var indexByKey: [String: Int] = [:]
    skipWhitespace()
    if position < bytes.count, bytes[position] == UInt8(ascii: "}") {
      position += 1
      return .object(fields)
    }
    while true {
      skipWhitespace()
      guard position < bytes.count, bytes[position] == UInt8(ascii: "\"") else { throw error("Expected key") }
      let key = try parseString()
      skipWhitespace()
      try expect(":")
      skipWhitespace()
      let value = try parseValue(depth: depth + 1)
      if let existing = indexByKey[key] {
        fields[existing].1 = value
      } else {
        indexByKey[key] = fields.count
        fields.append((key, value))
      }
      skipWhitespace()
      guard position < bytes.count else { throw error("Unterminated object") }
      if bytes[position] == UInt8(ascii: ",") {
        position += 1
        continue
      }
      try expect("}")
      return .object(fields)
    }
  }

  mutating func parseArray(depth: Int) throws(JSONParseError) -> JSONValue {
    position += 1
    var items: [JSONValue] = []
    skipWhitespace()
    if position < bytes.count, bytes[position] == UInt8(ascii: "]") {
      position += 1
      return .array(items)
    }
    while true {
      skipWhitespace()
      items.append(try parseValue(depth: depth + 1))
      skipWhitespace()
      guard position < bytes.count else { throw error("Unterminated array") }
      if bytes[position] == UInt8(ascii: ",") {
        position += 1
        continue
      }
      try expect("]")
      return .array(items)
    }
  }

  mutating func parseHex4() throws(JSONParseError) -> UInt16 {
    guard position + 4 <= bytes.count else { throw error("Bad unicode escape") }
    var value: UInt16 = 0
    for _ in 0..<4 {
      let byte = bytes[position]
      let digit: UInt16
      switch byte {
      case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt16(byte - UInt8(ascii: "0"))
      case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt16(byte - UInt8(ascii: "a") + 10)
      case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt16(byte - UInt8(ascii: "A") + 10)
      default: throw error("Bad unicode escape")
      }
      value = value * 16 + digit
      position += 1
    }
    return value
  }

  mutating func parseString() throws(JSONParseError) -> String {
    position += 1  // opening quote
    var utf16: [UInt16] = []
    var rawStart = position
    func flushRaw(_ end: Int) {
      if end > rawStart {
        utf16.append(contentsOf: (String(validating: bytes[rawStart..<end], as: UTF8.self) ?? "").utf16)
      }
    }
    while true {
      guard position < bytes.count else { throw error("Unterminated string") }
      let byte = bytes[position]
      if byte == UInt8(ascii: "\"") {
        flushRaw(position)
        position += 1
        return String(decoding: utf16, as: UTF16.self)
      }
      if byte < 0x20 { throw error("Control character in string") }
      if byte != UInt8(ascii: "\\") {
        position += 1
        continue
      }
      flushRaw(position)
      position += 1
      guard position < bytes.count else { throw error("Unterminated escape") }
      let escape = bytes[position]
      position += 1
      switch escape {
      case UInt8(ascii: "\""): utf16.append(0x22)
      case UInt8(ascii: "\\"): utf16.append(0x5C)
      case UInt8(ascii: "/"): utf16.append(0x2F)
      case UInt8(ascii: "b"): utf16.append(0x08)
      case UInt8(ascii: "f"): utf16.append(0x0C)
      case UInt8(ascii: "n"): utf16.append(0x0A)
      case UInt8(ascii: "r"): utf16.append(0x0D)
      case UInt8(ascii: "t"): utf16.append(0x09)
      case UInt8(ascii: "u"): utf16.append(try parseHex4())
      default:
        position -= 1
        throw error("Bad escape")
      }
      rawStart = position
    }
  }

  mutating func parseNumber() throws(JSONParseError) -> Double {
    let start = position
    func isDigit(_ i: Int) -> Bool { i < bytes.count && bytes[i] >= 0x30 && bytes[i] <= 0x39 }
    if bytes[position] == UInt8(ascii: "-") { position += 1 }
    guard isDigit(position) else { throw error("Bad number") }
    if bytes[position] == UInt8(ascii: "0") {
      position += 1
    } else {
      while isDigit(position) { position += 1 }
    }
    if position < bytes.count, bytes[position] == UInt8(ascii: ".") {
      position += 1
      guard isDigit(position) else { throw error("Bad number") }
      while isDigit(position) { position += 1 }
    }
    if position < bytes.count, bytes[position] == UInt8(ascii: "e") || bytes[position] == UInt8(ascii: "E") {
      position += 1
      if position < bytes.count, bytes[position] == UInt8(ascii: "+") || bytes[position] == UInt8(ascii: "-") {
        position += 1
      }
      guard isDigit(position) else { throw error("Bad number") }
      while isDigit(position) { position += 1 }
    }
    let text = String(validating: bytes[start..<position], as: UTF8.self) ?? ""
    guard let value = Double(text) else { throw error("Bad number") }
    return value
  }
}
