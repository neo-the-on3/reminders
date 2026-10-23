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
    var checks = [operatingSystemCheck(), infoPlistCheck(), hostCheck(), databaseCheck()]
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

  /// The guidance for this process: who holds the permissions and what to do about each access state.
  public var permissions: PermissionGuidance { PermissionGuidance(host: system.hostApplication) }

  /// Asks for Reminders access (the system prompt) if the user hasn't decided yet, checks database access, and
  /// opens System Settings for whatever is missing, narrating each step to `console`.
  /// Why `authorize` failed: the `PERMISSION_DENIED` (or `UNSUPPORTED_PLATFORM`) error for anything short of full
  /// Reminders access; nil once it is granted. Database access is only needed for sections, so it doesn't count.
  public func failure(of report: AuthorizationReport) -> RemindersError? {
    report.remindersAccess == .fullAccess ? nil : permissions.error(for: report.remindersAccess)
  }

  public func authorize(narratingTo console: Console) async -> AuthorizationReport {
    let style = console.style
    let name = ProductInfo.name
    let permissions = permissions
    let holder = permissions.holder
    console.narrate(
      style("\n\(name) authorize\n", .bold) + console.renderer.rule(20) + "\n\n"
        + style(
          """
          macOS grants these permissions to the app you run \(name) from (here: \(holder)),
          not to \(name) itself. You only need to do this once per app.\n
          """, .dim))

    func open(_ pane: SettingsPane, toEnable what: String) {
      console.narrate("     Opening System Settings — \(what).\n")
      if !system.openSettings(pane) { console.narrate(style("     Go to: \(pane.location)\n", .dim)) }
    }

    console.narrate("\n1. Checking Reminders access...\n")
    let before = await service.store.accessStatus()
    if before == .notDetermined {
      console.narrate(style("   If a system dialog appears, click Allow.\n", .dim))
    }
    var access = await service.requestAccess()
    var listCount: Int?
    if access == .fullAccess {
      do {
        listCount = try await service.lists().count
      } catch {
        access = await service.store.accessStatus()
      }
    }
    switch access {
    case .fullAccess:
      let count = listCount ?? 0
      console.narrate(
        "   \(style("✓", .green)) Reminders access granted (\(count) list\(count == 1 ? "" : "s") found)\n")
    case .unavailable:
      console.narrate(style("   ✗ Apple Reminders is not available on this platform.\n", .yellow))
    case .notDetermined:
      console.narrate(
        style("   ✗ macOS didn't show the Reminders prompt for \(holder).\n", .yellow)
          + "     \(permissions.unpromptedRemedy).\n")
    case .denied, .restricted, .writeOnly:
      console.narrate(style("   ✗ Reminders access: \(permissions.status(of: access) ?? "").\n", .yellow))
      if before != .notDetermined {
        console.narrate("     macOS won't show the prompt again; only System Settings can change this.\n")
      }
      console.narrate("     \(permissions.remedy(for: access) ?? "").\n")
      open(.reminders, toEnable: "enable \(holder) under Reminders")
    }

    console.narrate("\n2. Checking database access (for section features)...\n")
    let database = try? system.remindersDatabaseFiles().first
    if let database {
      let file = database.split(separator: "/").last.map(String.init) ?? database
      console.narrate("   \(style("✓", .green)) Database access granted (\(file))\n")
    } else {
      console.narrate(
        style("   ✗ Database access not yet granted.\n", .yellow)
          + "     Section features (create-section, move, etc.) need Full Disk Access for \(holder).\n")
      open(.fullDiskAccess, toEnable: "add \(holder) to Full Disk Access")
      console.narrate(style("     After enabling, restart \(holder) and run \(name) doctor.\n", .dim))
    }
    return AuthorizationReport(remindersAccess: access, databaseAccess: database != nil, host: system.hostApplication)
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

  /// Which app macOS asks about, so the user knows what to look for in System Settings.
  private func hostCheck() -> HealthCheck {
    guard let host = system.hostApplication else {
      return HealthCheck(
        "Permissions app", .warn, "Unknown",
        detail: "macOS attributes permissions to the app that started \(ProductInfo.name)")
    }
    return HealthCheck("Permissions app", .ok, host.name, detail: host.bundlePath)
  }

  private func databaseCheck() -> HealthCheck {
    let hint =
      "Run: \(ProductInfo.name) authorize (section features need Full Disk Access for \(permissions.holder))"
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
    let access = await service.store.accessStatus()
    guard access == .fullAccess else {
      return HealthCheck(
        "Reminders access", .fail, permissions.status(of: access) ?? "", detail: permissions.remedy(for: access))
    }
    do {
      let count = try await service.lists().count
      return HealthCheck("Reminders access", .ok, "Granted (\(count) list\(count == 1 ? "" : "s"))")
    } catch {
      return HealthCheck("Reminders access", .fail, "Error: \(error.message)", detail: error.suggestion)
    }
  }
}
