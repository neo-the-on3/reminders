/// One `reminders doctor` check.
public struct HealthCheck: Hashable, Sendable, Codable {
  public enum Status: String, Hashable, Sendable, Codable {
    case ok, warn, fail
  }

  public var name: String
  public var status: Status
  public var message: String
  public var detail: String?

  public init(_ name: String, _ status: Status, _ message: String, detail: String? = nil) {
    self.name = name
    self.status = status
    self.message = message
    self.detail = detail
  }
}

/// `reminders doctor`: the checks, or in JSON their array.
public struct HealthReport: ConsoleRepresentable {
  public var checks: [HealthCheck]

  public init(_ checks: [HealthCheck]) {
    self.checks = checks
  }

  public var failureCount: Int { checks.count { $0.status == .fail } }
  public var passed: Bool { failureCount == 0 }

  public func encode(to encoder: any Encoder) throws { try checks.encode(to: encoder) }

  public func text(using renderer: TextRenderer) -> String {
    let style = renderer.style
    var text = style("\n\(ProductInfo.name) doctor\n", .bold) + renderer.rule(40) + "\n"
    for check in checks {
      let icon =
        switch check.status {
        case .ok: style("✓", .green)
        case .warn: style("⚠", .yellow)
        case .fail: style("✗", .red)
        }
      text += "\(icon) \(style(check.name, .bold)): \(check.message)\n"
      if let detail = check.detail { text += style("  \(detail)\n", .dim) }
    }
    text += passed ? style("\nAll checks passed.\n", .green) : style("\n\(failureCount) issue(s) found.\n", .red)
    return text
  }
}

/// `reminders authorize`: what access the process ended up with. The text form is the closing hint; the steps
/// are narrated as they happen.
public struct AuthorizationReport: ConsoleRepresentable {
  public var remindersAccess: ReminderAccess
  public var databaseAccess: Bool
  /// The app the permissions belong to, when known.
  public var host: HostApplication?

  public init(remindersAccess: ReminderAccess, databaseAccess: Bool, host: HostApplication? = nil) {
    self.remindersAccess = remindersAccess
    self.databaseAccess = databaseAccess
    self.host = host
  }

  public func text(using renderer: TextRenderer) -> String {
    renderer.style("\nRun '\(ProductInfo.name) doctor' to verify all permissions.\n\n", .dim)
  }
}
