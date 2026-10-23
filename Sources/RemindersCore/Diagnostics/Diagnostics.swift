/// `doctor` and `authorize`.
public struct Diagnostics: Sendable {
  public var service: RemindersService
  public var system: any SystemProbe

  public init(service: RemindersService, system: any SystemProbe) {
    self.service = service
    self.system = system
  }

  /// Runs every check. Never shows the Reminders prompt (it would wait for an answer); `authorize` does that.
  public func checkHealth(includeDatabaseStats: Bool = false, includeSync: Bool = false) async -> HealthReport {
    var checks = [operatingSystemCheck(), infoPlistCheck(), databaseCheck()]
    if includeDatabaseStats {
      checks.append(
        HealthCheck(
          "Database stats", .warn, "Not available yet", detail: "Database statistics arrive with section support"))
    }
    if includeSync {
      checks.append(
        HealthCheck("Sync", .warn, "Not available yet", detail: "Sync checks arrive with section support"))
    }
    checks.append(await accessCheck())
    checks.append(
      system.remindersDataDirectoryExists()
        ? HealthCheck("Reminders data dir", .ok, "Exists")
        : HealthCheck("Reminders data dir", .fail, "Not found", detail: system.remindersDataDirectory))
    return HealthReport(checks)
  }

  /// Asks for Reminders access (the system prompt), checks database access, and opens System Settings for
  /// whatever is missing, narrating each step to `console`.
  public func authorize(narratingTo console: Console) async -> AuthorizationReport {
    let style = console.style
    let name = ProductInfo.name
    console.narrate(
      style("\n\(name) authorize\n", .bold) + console.renderer.rule(20) + "\n\n"
        + style(
          """
          macOS grants permissions to your terminal app (Terminal, iTerm, Cursor, etc.),
          not to \(name) directly. You only need to do this once per terminal app.\n
          """, .dim))

    func open(_ pane: SettingsPane, toEnable what: String) {
      console.narrate("     Opening System Settings — \(what).\n")
      if !system.openSettings(pane) { console.narrate(style("     Go to: \(pane.location)\n", .dim)) }
    }
    let restartHint = style("     After enabling, restart your terminal and run \(name) authorize again.\n", .dim)

    console.narrate(
      "\n1. Checking Reminders access...\n" + style("   If a system dialog appears, click Allow.\n", .dim))
    var access = await service.store.accessStatus()
    do {
      let count = try await service.lists().count
      access = .fullAccess
      console.narrate(
        "   \(style("✓", .green)) Reminders access granted (\(count) list\(count == 1 ? "" : "s") found)\n")
    } catch {
      access = await service.store.accessStatus()
      console.narrate(style("   ✗ Reminders access not granted.\n", .yellow))
      open(.reminders, toEnable: "enable your terminal app under Reminders")
      console.narrate(restartHint)
    }

    console.narrate("\n2. Checking database access (for section features)...\n")
    let database = try? system.remindersDatabaseFiles().first
    if let database {
      let file = database.split(separator: "/").last.map(String.init) ?? database
      console.narrate("   \(style("✓", .green)) Database access granted (\(file))\n")
    } else {
      console.narrate(
        style("   ✗ Database access not yet granted.\n", .yellow)
          + "     Section features (create-section, move, etc.) need Full Disk Access.\n")
      open(.fullDiskAccess, toEnable: "add your terminal app to Full Disk Access")
      console.narrate(restartHint)
    }
    return AuthorizationReport(remindersAccess: access, databaseAccess: database != nil)
  }

  // MARK: Checks

  private func operatingSystemCheck() -> HealthCheck {
    guard let version = system.operatingSystemVersion else {
      return HealthCheck("macOS version", .fail, "Could not determine macOS version")
    }
    let major = version.split(separator: ".").first.flatMap { Int($0) } ?? 0
    return major >= 26
      ? HealthCheck("macOS version", .ok, "macOS \(version)")
      : HealthCheck("macOS version", .fail, "macOS \(version) (requires 26+)")
  }

  /// macOS only shows the Reminders prompt to executables that carry a usage description.
  private func infoPlistCheck() -> HealthCheck {
    guard let plist = system.embeddedInfoPlist, plist["NSRemindersFullAccessUsageDescription"] != nil else {
      return HealthCheck(
        "Info.plist", .warn, "Not embedded — macOS may not show the Reminders prompt",
        detail: "Build with: scripts/build-release.sh")
    }
    return HealthCheck("Info.plist", .ok, "Embedded (\(plist["CFBundleIdentifier"] ?? "no identifier"))")
  }

  private func databaseCheck() -> HealthCheck {
    let hint = "Run: \(ProductInfo.name) authorize (section features need Full Disk Access for your terminal app)"
    do {
      guard let first = try system.remindersDatabaseFiles().first else {
        return HealthCheck(
          "Reminders database", .warn,
          "Not accessible (No active Reminders database found in \(system.remindersDataDirectory))", detail: hint)
      }
      return HealthCheck("Reminders database", .ok, "Found", detail: first)
    } catch {
      return HealthCheck("Reminders database", .warn, "Not accessible (\(error.message))", detail: hint)
    }
  }

  private func accessCheck() async -> HealthCheck {
    let hint = "Run: \(ProductInfo.name) authorize"
    switch await service.store.accessStatus() {
    case .notDetermined:
      return HealthCheck("Reminders access", .fail, "Not requested yet", detail: hint)
    case .fullAccess:
      do {
        let count = try await service.lists().count
        return HealthCheck("Reminders access", .ok, "Granted (\(count) list\(count == 1 ? "" : "s"))")
      } catch {
        return HealthCheck("Reminders access", .fail, "Error: \(error.message)", detail: hint)
      }
    case .writeOnly:
      return HealthCheck("Reminders access", .fail, "Write-only (full access needed)", detail: hint)
    case .denied, .restricted:
      return HealthCheck("Reminders access", .fail, "Not granted", detail: hint)
    case .unavailable:
      return HealthCheck("Reminders access", .fail, "Apple Reminders is not available on this platform")
    }
  }
}
