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
    var checks = [operatingSystemCheck(), infoPlistCheck(), hostCheck(), reminderKitCheck()]
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
    return HealthReport(checks)
  }

  /// The guidance for this process: who holds the permissions and what to do about each access state.
  public var permissions: PermissionGuidance { PermissionGuidance(host: system.hostApplication) }

  /// Why `authorize` failed: the `PERMISSION_DENIED` (or `UNSUPPORTED_PLATFORM`) error for anything short of full
  /// Reminders access; nil once it is granted.
  public func failure(of report: AuthorizationReport) -> RemindersError? {
    report.remindersAccess == .fullAccess ? nil : permissions.error(for: report.remindersAccess)
  }

  /// Asks for Reminders access (the system prompt) if the user hasn't decided yet, and opens System Settings when
  /// it's missing, narrating each step to `console`. Reminders access is the only permission needed: sections go
  /// through ReminderKit, not Reminders' database.
  public func authorize(narratingTo console: Console) async -> AuthorizationReport {
    let style = console.style
    let name = ProductInfo.name
    let permissions = permissions
    let holder = permissions.holder
    let attribution =
      permissions.holderIsThisTool
      ? """
      Here macOS grants Reminders access to \(name) itself, not to the app that started it.
      You only need to do this once.\n
      """
      : """
      macOS grants Reminders access to the app you run \(name) from (here: \(holder)),
      not to \(name) itself. You only need to do this once per app.\n
      """
    console.narrate(
      style("\n\(name) authorize\n", .bold) + console.renderer.rule(20) + "\n\n" + style(attribution, .dim))

    func open(_ pane: SettingsPane, toEnable what: String) {
      console.narrate("     Opening System Settings — \(what).\n")
      if !system.openSettings(pane) { console.narrate(style("     Go to: \(pane.location)\n", .dim)) }
    }

    console.narrate("\nChecking Reminders access...\n")
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

    return AuthorizationReport(remindersAccess: access, host: system.hostApplication)
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
    return HealthCheck(
      "Permissions app", .ok, host.isThisTool ? "\(host.name) (this tool)" : host.name, detail: host.bundlePath)
  }

  /// Sections need ReminderKit; everything else works without it.
  private func reminderKitCheck() -> HealthCheck {
    guard let problem = system.reminderKitProblem() else {
      return HealthCheck("Sections (ReminderKit)", .ok, "Available")
    }
    return HealthCheck(
      "Sections (ReminderKit)", .warn, "Unavailable (\(problem))",
      detail: "Everything except sections works; report it at \(ProductInfo.homepage)/issues with your macOS version")
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
