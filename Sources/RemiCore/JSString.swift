// Small helpers reproducing JavaScript string semantics that remi relies on.
//
// JavaScript compares strings by UTF-16 code units and measures `length` in UTF-16 code units,
// whereas Swift compares by canonical equivalence and counts grapheme clusters. Using these helpers
// keeps matching and column alignment identical to the TypeScript implementation.

extension String {
  /// `a === b` in JavaScript (code-unit equality).
  func jsEquals(_ other: String) -> Bool {
    utf16.elementsEqual(other.utf16)
  }

  /// `haystack.includes(needle)` in JavaScript. An empty needle always matches.
  func jsIncludes(_ needle: String) -> Bool {
    let h = Array(utf16)
    let n = Array(needle.utf16)
    if n.isEmpty { return true }
    if n.count > h.count { return false }
    for start in 0...(h.count - n.count) where h[start] == n[0] {
      var matched = true
      for offset in 1..<n.count where h[start + offset] != n[offset] {
        matched = false
        break
      }
      if matched { return true }
    }
    return false
  }

  /// `toLowerCase()` in JavaScript (locale-independent).
  var jsLowercased: String { lowercased() }

  /// `length` in JavaScript.
  var jsLength: Int { utf16.count }

  /// `padEnd(length)` in JavaScript (pads with spaces, measured in UTF-16 code units).
  func jsPadEnd(_ length: Int) -> String {
    let missing = length - jsLength
    return missing > 0 ? self + String(repeating: " ", count: missing) : self
  }

  /// `padStart(length)` in JavaScript.
  func jsPadStart(_ length: Int) -> String {
    let missing = length - jsLength
    return missing > 0 ? String(repeating: " ", count: missing) + self : self
  }

  /// `substring(0, length)` in JavaScript (UTF-16 code units).
  func jsPrefix(_ length: Int) -> String {
    String(decoding: utf16.prefix(length), as: UTF16.self)
  }

  /// `trim()` in JavaScript: strips Unicode whitespace and line terminators from both ends.
  var jsTrimmed: String {
    let scalars = unicodeScalars
    guard let first = scalars.firstIndex(where: { !$0.isJSWhitespace }) else { return "" }
    let last = scalars.lastIndex(where: { !$0.isJSWhitespace })!
    return String(scalars[first...last])
  }
}

extension Unicode.Scalar {
  /// JavaScript's WhiteSpace + LineTerminator set (used by `trim()` and `\s`).
  var isJSWhitespace: Bool {
    switch value {
    case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
      0x3000, 0xFEFF:
      return true
    default:
      return false
    }
  }
}
