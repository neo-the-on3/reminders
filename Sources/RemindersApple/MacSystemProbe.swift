import Foundation
import RemindersCore

/// The real ``SystemProbe``. Off macOS it knows no version, no Info.plist and can't open anything.
public struct MacSystemProbe: SystemProbe {
  public init() {}

  public var operatingSystemVersion: String? {
    #if os(macOS)
      let version = ProcessInfo.processInfo.operatingSystemVersion
      let base = "\(version.majorVersion).\(version.minorVersion)"
      return version.patchVersion == 0 ? base : "\(base).\(version.patchVersion)"
    #else
      return nil
    #endif
  }

  /// Foundation exposes an unbundled executable's `__TEXT,__info_plist` section as `Bundle.main.infoDictionary`.
  public var embeddedInfoPlist: [String: String]? {
    #if os(macOS)
      guard let info = Bundle.main.infoDictionary, info["NSRemindersFullAccessUsageDescription"] != nil else {
        return nil
      }
      return info.compactMapValues { $0 as? String }
    #else
      return nil
    #endif
  }

  public var remindersDataDirectory: String {
    FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Group Containers/group.com.apple.reminders/Container_v1/Stores").path
  }

  public func remindersDataDirectoryExists() -> Bool {
    FileManager.default.fileExists(atPath: remindersDataDirectory)
  }

  /// Listing this directory needs Full Disk Access for the terminal app.
  public func remindersDatabaseFiles() throws(RemindersError) -> [String] {
    let directory = remindersDataDirectory
    guard remindersDataDirectoryExists() else {
      throw RemindersError(.databaseNotFound, "Reminders data directory not found at \(directory)")
    }
    let names: [String]
    do {
      names = try FileManager.default.contentsOfDirectory(atPath: directory)
    } catch {
      throw RemindersError(.permissionDenied, "Cannot access Reminders database — permission denied")
    }
    return names.filter { $0.hasSuffix(".sqlite") }.sorted().map { "\(directory)/\($0)" }
  }

  public func openSettings(_ pane: SettingsPane) -> Bool {
    #if os(macOS)
      let process = Process()
      process.executableURL = URL(filePath: "/usr/bin/open")
      process.arguments = [pane.url]
      do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
      } catch {
        return false
      }
    #else
      return false
    #endif
  }
}
