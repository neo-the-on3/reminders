// Ported from remi src/cli/commands/doctor.ts and authorize.ts (MIT, Matthew O'Riordan).

/// Facts about the machine that `doctor` and `authorize` look at. RemiApple provides the real one.
public protocol SystemEnvironment {
  /// `sw_vers -productVersion`, e.g. "26.0.1"; nil when unknown.
  var productVersion: String? { get }
  /// The `__TEXT,__info_plist` section embedded in the running binary, if any.
  var embeddedInfoPlist: [String: String]? { get }
  /// `~/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores`
  var remindersStoresPath: String { get }
  /// Whether ``remindersStoresPath`` exists.
  func remindersStoresExist() -> Bool
  /// The `.sqlite` files in the stores directory. Throws when it can't be read (no Full Disk Access).
  func remindersDatabaseFiles() throws -> [String]
  /// `open <url>`; returns false when that failed.
  func open(_ url: String) -> Bool
}

/// One `remi doctor` check.
public struct DoctorCheck: Equatable, Sendable, JSONValueConvertible {
  public enum Status: String, Sendable { case ok, warn, fail }

  public var name: String
  public var status: Status
  public var message: String
  public var detail: String?

  public init(name: String, status: Status, message: String, detail: String? = nil) {
    self.name = name
    self.status = status
    self.message = message
    self.detail = detail
  }

  public var jsonValue: JSONValue {
    var fields: [(String, JSONValue)] = [
      ("name", .string(name)), ("status", .string(status.rawValue)), ("message", .string(message)),
    ]
    if let detail { fields.append(("detail", .string(detail))) }
    return .object(fields)
  }
}

/// Bundle identifier embedded in remi's Info.plist (Support/Info.plist).
public let remiBundleIdentifier = "io.github.neo-the-on3.remi"

let remindersSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
let fullDiskAccessSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

extension CommandContext {
  /// Run remi's checks. They never show the Reminders permission prompt.
  public func doctorChecks(system: some SystemEnvironment, databaseStats: Bool = false) async -> [DoctorCheck] {
    var checks: [DoctorCheck] = []

    if let version = system.productVersion {
      let major = jsParseInt(version.split(separator: ".").first.map(String.init) ?? "") ?? 0
      checks.append(
        major >= 26
          ? DoctorCheck(name: "macOS version", status: .ok, message: "macOS \(version)")
          : DoctorCheck(name: "macOS version", status: .fail, message: "macOS \(version) (requires 26+)"))
    } else {
      checks.append(DoctorCheck(name: "macOS version", status: .fail, message: "Could not determine macOS version"))
    }

    // Replaces remi's "Swift" and "reminders-helper" checks: this binary *is* the helper, and the
    // permission prompt depends on its embedded Info.plist.
    let plist = system.embeddedInfoPlist
    if let plist, plist["NSRemindersFullAccessUsageDescription"] != nil {
      checks.append(
        DoctorCheck(
          name: "Info.plist", status: .ok, message: "Embedded (\(plist["CFBundleIdentifier"] ?? "no identifier"))"))
    } else {
      checks.append(
        DoctorCheck(
          name: "Info.plist", status: .warn, message: "Not embedded — macOS may not show the Reminders prompt",
          detail: "Build with: scripts/build-release.sh"))
    }

    checks.append(databaseCheck(system: system))
    if databaseStats {
      checks.append(
        DoctorCheck(
          name: "Database stats", status: .warn, message: "Not available yet in the Swift port",
          detail: "Database statistics arrive with the sections layer"))
    }

    checks.append(await accessCheck())

    checks.append(
      system.remindersStoresExist()
        ? DoctorCheck(name: "Reminders data dir", status: .ok, message: "Exists")
        : DoctorCheck(
          name: "Reminders data dir", status: .fail, message: "Not found", detail: system.remindersStoresPath))
    return checks
  }

  func databaseCheck(system: some SystemEnvironment) -> DoctorCheck {
    do {
      let files = try system.remindersDatabaseFiles()
      guard let first = files.first else {
        throw RemiCommandError(.dbNotFound, "No active Reminders database found in \(system.remindersStoresPath)")
      }
      return DoctorCheck(name: "Reminders database", status: .ok, message: "Found", detail: first)
    } catch {
      return DoctorCheck(
        name: "Reminders database", status: .warn, message: "Not accessible (\(describe(error)))",
        detail: "Run: remi authorize (section features need Full Disk Access for your terminal app)")
    }
  }

  func accessCheck() async -> DoctorCheck {
    // Unlike remi, doctor never triggers the permission prompt (it would wait for an answer); authorize does.
    if store.accessStatus() == .notDetermined {
      return DoctorCheck(
        name: "Reminders access", status: .fail, message: "Not requested yet", detail: "Run: remi authorize")
    }
    do {
      let count = try await listLists().count
      if count > 0 {
        return DoctorCheck(name: "Reminders access", status: .ok, message: "Granted (\(count) lists)")
      }
      return DoctorCheck(
        name: "Reminders access", status: .fail, message: "Not granted (0 lists returned)",
        detail: "Run: remi authorize")
    } catch let error as RemiCommandError where error.code == .permissionDenied {
      return DoctorCheck(name: "Reminders access", status: .fail, message: "Not granted", detail: "Run: remi authorize")
    } catch {
      return DoctorCheck(
        name: "Reminders access", status: .fail, message: "Error: \(describe(error))", detail: "Run: remi authorize")
    }
  }

  /// `remi doctor`. Returns false when a check failed (the CLI then exits 1).
  public func doctor(system: some SystemEnvironment, databaseStats: Bool = false) async -> Bool {
    let checks = await doctorChecks(system: system, databaseStats: databaseStats)
    if output.jsonMode {
      output.success(JSONValue.array(checks.map(\.jsonValue)))
      return true
    }
    let style = output.style
    var text = style("\nremi doctor\n", .bold) + String(repeating: "─", count: 40) + "\n"
    for check in checks {
      let icon: String
      switch check.status {
      case .ok: icon = style("✓", .green)
      case .warn: icon = style("⚠", .yellow)
      case .fail: icon = style("✗", .red)
      }
      text += "\(icon) \(style(check.name, .bold)): \(check.message)\n"
      if let detail = check.detail { text += style("  \(detail)\n", .dim) }
    }
    let failures = checks.filter { $0.status == .fail }.count
    text +=
      failures > 0
      ? style("\n\(failures) issue(s) found.\n", .red) : style("\nAll checks passed.\n", .green)
    output.stdout.write(text)
    return failures == 0
  }

  /// `remi authorize`: trigger the Reminders prompt and open System Settings for anything missing.
  /// Prints nothing in JSON mode, like remi.
  public func authorize(system: some SystemEnvironment) async {
    let style = output.style
    func out(_ text: String) { if !output.jsonMode { output.stdout.write(text) } }

    out(style("\nremi authorize\n", .bold))
    out(String(repeating: "─", count: 20) + "\n\n")
    out(
      style(
        "macOS grants permissions to your terminal app (Terminal, iTerm, Cursor, etc.),\nnot to remi directly. You only need to do this once per terminal app.\n",
        .dim))

    out("\n1. Checking Reminders access...\n")
    out(style("   If a system dialog appears, click Allow.\n", .dim))
    func openReminders() {
      out("     Opening System Settings — enable your terminal app under Reminders.\n")
      if !system.open(remindersSettingsURL) {
        out(style("     Go to: System Settings > Privacy & Security > Reminders\n", .dim))
      }
    }
    do {
      let count = try await listLists().count
      if count > 0 {
        out("   \(style("✓", .green)) Reminders access granted (\(count) list\(count == 1 ? "" : "s") found)\n")
      } else {
        out(style("   ✗ Reminders access appears denied (0 lists returned)\n", .yellow))
        openReminders()
        out(style("     After enabling, restart your terminal and run remi authorize again.\n", .dim))
      }
    } catch {
      out(style("   ✗ Reminders access not granted.\n", .yellow))
      openReminders()
    }

    out("\n2. Checking database access (for section features)...\n")
    if let first = try? system.remindersDatabaseFiles().first {
      let name = first.split(separator: "/").last.map(String.init) ?? first
      out("   \(style("✓", .green)) Database access granted (\(name))\n")
    } else {
      out(style("   ✗ Database access not yet granted.\n", .yellow))
      out("     Section features (create-section, move, etc.) need Full Disk Access.\n")
      out("     Opening System Settings — add your terminal app to Full Disk Access.\n")
      if !system.open(fullDiskAccessSettingsURL) {
        out(style("     Go to: System Settings > Privacy & Security > Full Disk Access\n", .dim))
      }
      out(style("     After enabling, restart your terminal and run remi authorize again.\n", .dim))
    }

    out(style("\nRun 'remi doctor' to verify all permissions.\n\n", .dim))
  }
}

func describe(_ error: any Error) -> String {
  if let error = error as? RemiCommandError { return error.message }
  return "\(error)"
}
