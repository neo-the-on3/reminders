/// How many colours the terminal supports.
public enum ColorSupport: Int, Comparable, Sendable {
  case none, basic, ansi256, trueColor

  public static func < (lhs: ColorSupport, rhs: ColorSupport) -> Bool { lhs.rawValue < rhs.rawValue }

  /// Detects support from the environment: `FORCE_COLOR` / `NO_COLOR` first, then whether stdout is a terminal,
  /// `TERM` and `COLORTERM`.
  public static func detect(isTerminal: Bool, environment: [String: String]) -> ColorSupport {
    if let force = environment["FORCE_COLOR"] {
      switch force {
      case "0", "false": return .none
      case "2": return .ansi256
      case "3": return .trueColor
      default: return .basic
      }
    }
    if environment["NO_COLOR"] != nil { return .none }
    guard isTerminal else { return .none }
    let term = environment["TERM"] ?? ""
    if term == "dumb" { return .none }
    if let colorTerm = environment["COLORTERM"], colorTerm == "truecolor" || colorTerm == "24bit" { return .trueColor }
    if term.hasSuffix("256color") || term.hasSuffix("256") { return .ansi256 }
    return .basic
  }
}

/// A text attribute the human-readable output uses.
public enum TextAttribute: Sendable {
  case bold, dim, underline, strikethrough
  case red, green, yellow, blue, magenta, cyan
  /// Reminders.app's flag orange (#FF9500), approximated on terminals without true colour.
  case orange

  fileprivate func escapes(for support: ColorSupport) -> (open: String, close: String) {
    let (open, close): (String, String) =
      switch self {
      case .bold: ("1", "22")
      case .dim: ("2", "22")
      case .underline: ("4", "24")
      case .strikethrough: ("9", "29")
      case .red: ("31", "39")
      case .green: ("32", "39")
      case .yellow: ("33", "39")
      case .blue: ("34", "39")
      case .magenta: ("35", "39")
      case .cyan: ("36", "39")
      case .orange:
        switch support {
        case .trueColor: ("38;2;255;149;0", "39")
        case .ansi256: ("38;5;214", "39")
        default: ("93", "39")
        }
      }
    return ("\u{1B}[\(open)m", "\u{1B}[\(close)m")
  }
}

/// Wraps text in ANSI escape sequences, or leaves it alone when colour is off.
public struct TerminalStyle: Sendable {
  public var support: ColorSupport

  public init(_ support: ColorSupport) {
    self.support = support
  }

  public static let plain = TerminalStyle(.none)

  /// `text` with `attributes` applied, outermost first.
  public func callAsFunction(_ text: String, _ attributes: TextAttribute...) -> String {
    guard support > .none, !attributes.isEmpty, !text.isEmpty else { return text }
    let escapes = attributes.map { $0.escapes(for: support) }
    let open = escapes.map(\.open).joined()
    let close = escapes.reversed().map(\.close).joined()
    var body = text
    // A nested close sequence would also end an outer attribute that shares it, so re-open the outer one.
    for escape in escapes.reversed() where body.contains(escape.close) {
      body = body.replacing(escape.close, with: escape.close + escape.open)
    }
    // Close and re-open around line breaks so pagers and wrapped lines keep the styling.
    // "\r\n" is a single Character, so the second replacement only sees lone "\n".
    body = body.replacing("\r\n", with: close + "\r\n" + open).replacing("\n", with: close + "\n" + open)
    return open + body + close
  }
}
