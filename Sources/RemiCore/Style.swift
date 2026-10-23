// Minimal ANSI styling that reproduces the escape sequences chalk emits for remi's output.

/// Text styles used by remi's human-readable output.
public enum StyleAttribute: Sendable {
  case bold, dim, underline, strikethrough
  case red, green, yellow, blue, magenta, cyan
  /// chalk.hex("#FF9500"), used for the flagged badge.
  case orange

  fileprivate func codes(level: ColorLevel) -> (open: String, close: String) {
    switch self {
    case .bold: return ("\u{1B}[1m", "\u{1B}[22m")
    case .dim: return ("\u{1B}[2m", "\u{1B}[22m")
    case .underline: return ("\u{1B}[4m", "\u{1B}[24m")
    case .strikethrough: return ("\u{1B}[9m", "\u{1B}[29m")
    case .red: return ("\u{1B}[31m", "\u{1B}[39m")
    case .green: return ("\u{1B}[32m", "\u{1B}[39m")
    case .yellow: return ("\u{1B}[33m", "\u{1B}[39m")
    case .blue: return ("\u{1B}[34m", "\u{1B}[39m")
    case .magenta: return ("\u{1B}[35m", "\u{1B}[39m")
    case .cyan: return ("\u{1B}[36m", "\u{1B}[39m")
    case .orange:
      switch level {
      case .trueColor: return ("\u{1B}[38;2;255;149;0m", "\u{1B}[39m")
      case .ansi256: return ("\u{1B}[38;5;214m", "\u{1B}[39m")
      default: return ("\u{1B}[93m", "\u{1B}[39m")
      }
    }
  }
}

/// Colour support level, mirroring chalk's levels.
public enum ColorLevel: Int, Sendable, Comparable {
  case none = 0, basic = 1, ansi256 = 2, trueColor = 3

  public static func < (lhs: ColorLevel, rhs: ColorLevel) -> Bool { lhs.rawValue < rhs.rawValue }

  /// Detect like chalk/supports-color: FORCE_COLOR / NO_COLOR, TTY, TERM, COLORTERM.
  public static func detect(isTTY: Bool, environment: [String: String]) -> ColorLevel {
    if let force = environment["FORCE_COLOR"] {
      switch force {
      case "0", "false": return .none
      case "2": return .ansi256
      case "3": return .trueColor
      default: return .basic
      }
    }
    if environment["NO_COLOR"] != nil { return .none }
    guard isTTY else { return .none }
    let term = environment["TERM"] ?? ""
    if term == "dumb" { return .none }
    if let colorTerm = environment["COLORTERM"], colorTerm == "truecolor" || colorTerm == "24bit" { return .trueColor }
    if term.hasSuffix("-256color") || term.hasSuffix("256") { return .ansi256 }
    return .basic
  }
}

/// Applies styles, or passes text through unchanged when colour is disabled.
public struct Styler: Sendable {
  public var level: ColorLevel

  public init(level: ColorLevel) { self.level = level }

  public static let plain = Styler(level: .none)

  /// Apply `attributes` (outermost first, like `chalk.bold.underline`).
  public func callAsFunction(_ text: String, _ attributes: StyleAttribute...) -> String {
    apply(text, attributes)
  }

  public func apply(_ text: String, _ attributes: [StyleAttribute]) -> String {
    guard level > .none, !attributes.isEmpty, !text.isEmpty else { return text }
    let pairs = attributes.map { $0.codes(level: level) }
    let openAll = pairs.map(\.open).joined()
    let closeAll = pairs.reversed().map(\.close).joined()
    var body = text
    // chalk re-opens an outer style after an inner close sequence that would cancel it
    for pair in pairs.reversed() where body.contains(pair.close) {
      body = body.replacingAll(pair.close, with: pair.close + pair.open)
    }
    // chalk closes and re-opens styles around line breaks
    if body.contains("\n") {
      body = body.replacingAll("\r\n", with: "\u{0}").replacingAll("\n", with: closeAll + "\n" + openAll)
        .replacingAll("\u{0}", with: closeAll + "\r\n" + openAll)
    }
    return openAll + body + closeAll
  }
}

extension String {
  fileprivate func replacingAll(_ target: String, with replacement: String) -> String {
    guard !target.isEmpty else { return self }
    var result = ""
    var remainder = self[...]
    while let range = remainder.firstRange(of: target) {
      result += remainder[..<range.lowerBound]
      result += replacement
      remainder = remainder[range.upperBound...]
    }
    result += remainder
    return result
  }
}
