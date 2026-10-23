import Foundation
import Synchronization
import Testing

@testable import RemindersCore

/// A machine whose facts the test chooses.
private final class FakeSystem: SystemProbe {
  let operatingSystemVersion: String?
  let embeddedInfoPlist: [String: String]?
  let remindersDataDirectory = "/Users/test/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores"
  private let databases: [String]?
  private let opened = Mutex<[SettingsPane]>([])

  init(version: String? = "26.1", plist: Bool = true, databases: [String]? = ["Data-1.sqlite"]) {
    operatingSystemVersion = version
    embeddedInfoPlist =
      plist
      ? ["CFBundleIdentifier": ProductInfo.bundleIdentifier, "NSRemindersFullAccessUsageDescription": "Needed"] : nil
    self.databases = databases
  }

  var hostApplication: HostApplication? { HostApplication(name: "Terminal", bundlePath: Self.terminalPath) }
  static let terminalPath = "/System/Applications/Utilities/Terminal.app"

  var openedPanes: [SettingsPane] { opened.withLock { $0 } }

  func remindersDataDirectoryExists() -> Bool { databases != nil }

  func remindersDatabaseFiles() throws(RemindersError) -> [String] {
    guard let databases else { throw RemindersError(.permissionDenied, "Cannot access Reminders database") }
    return databases.map { "\(remindersDataDirectory)/\($0)" }
  }

  func openSettings(_ pane: SettingsPane) -> Bool {
    opened.withLock { $0.append(pane) }
    return true
  }
}

private func diagnostics(access: ReminderAccess = .fullAccess, system: FakeSystem = FakeSystem()) -> Diagnostics {
  let store = InMemoryReminderStore(lists: [ReminderList(id: "L", title: "Inbox")], access: access)
  return Diagnostics(service: RemindersService(store: store, clock: utcClock), system: system)
}

@Suite("Diagnostics")
struct DiagnosticsTests {
  @Test("a healthy Mac passes every check")
  func healthy() async {
    let report = await diagnostics().checkHealth()
    #expect(report.passed)
    #expect(
      report.checks.map(\.name) == [
        "macOS version", "Info.plist", "Reminders database", "Reminders access", "Reminders data dir",
      ])
    #expect(report.checks.allSatisfy { $0.status == .ok })
    #expect(report.checks[3].message == "Granted (1 list)")
  }

  @Test("doctor never prompts: undecided access fails with a hint")
  func undecided() async throws {
    let report = await diagnostics(access: .notDetermined).checkHealth()
    let access = try #require(report.checks.first { $0.name == "Reminders access" })
    #expect(access.status == .fail)
    #expect(access.message == "Not requested yet")
    #expect(access.detail == "Run: reminders authorize")
  }

  @Test("old macOS fails; a missing Info.plist and database access warn")
  func problems() async {
    let report = await diagnostics(system: FakeSystem(version: "15.4", plist: false, databases: nil)).checkHealth(
      includeDatabaseStats: true, includeSync: true)
    let statuses = Dictionary(uniqueKeysWithValues: report.checks.map { ($0.name, $0.status) })
    #expect(statuses["macOS version"] == .fail)
    #expect(statuses["Info.plist"] == .warn)
    #expect(statuses["Reminders database"] == .warn)
    #expect(statuses["Database stats"] == .warn)
    #expect(statuses["Sync"] == .warn)
    #expect(statuses["Reminders data dir"] == .fail)
    #expect(report.failureCount == 2)
  }

  @Test("the text report matches the reference layout")
  func text() async {
    let (console, output, _) = makeConsole()
    console.show(await diagnostics(access: .denied).checkHealth())
    #expect(
      output.text == """

        reminders doctor
        ────────────────────────────────────────
        ✓ macOS version: macOS 26.1
        ✓ Info.plist: Embedded (io.github.neo-the-on3.reminders)
        ✓ Reminders database: Found
          /Users/test/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores/Data-1.sqlite
        ✗ Reminders access: Not granted
          Run: reminders authorize
        ✓ Reminders data dir: Exists

        1 issue(s) found.

        """)
  }

  @Test("authorize asks for access and opens Settings only for what's missing")
  func authorize() async {
    let system = FakeSystem(databases: nil)
    let (console, output, _) = makeConsole()
    let result = await diagnostics(access: .notDetermined, system: system).authorize(narratingTo: console)
    #expect(result.remindersAccess == .fullAccess)
    #expect(!result.databaseAccess)
    #expect(system.openedPanes == [.fullDiskAccess])
    #expect(output.text.contains("✓ Reminders access granted (1 list found)"))
    #expect(output.text.contains("✗ Database access not yet granted."))
  }

  @Test("authorize with --json prints only the outcome")
  func authorizeJSON() async {
    let (console, output, _) = makeConsole(json: true)
    console.show(await diagnostics(access: .denied).authorize(narratingTo: console))
    #expect(
      output.text == """
        {
          "data" : {
            "databaseAccess" : true,
            "remindersAccess" : "denied"
          },
          "success" : true
        }

        """)
  }
}
