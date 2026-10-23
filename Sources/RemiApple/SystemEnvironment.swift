// The machine facts `remi doctor` and `remi authorize` check (ported from remi's doctor.ts/authorize.ts).

import Foundation
import RemiCore

/// The real ``SystemEnvironment``. On Linux it reports what it can (nothing Reminders-related exists).
struct MacSystemEnvironment: SystemEnvironment {
  var productVersion: String? {
    #if os(macOS)
      let v = ProcessInfo.processInfo.operatingSystemVersion
      // Same shape as `sw_vers -productVersion`: "26.0", "26.0.1"
      return v.patchVersion == 0
        ? "\(v.majorVersion).\(v.minorVersion)" : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    #else
      return nil
    #endif
  }

  /// CoreFoundation reads an unbundled executable's `__TEXT,__info_plist` section into `Bundle.main`.
  var embeddedInfoPlist: [String: String]? {
    #if os(macOS)
      guard let info = Bundle.main.infoDictionary, info["NSRemindersFullAccessUsageDescription"] != nil else {
        return nil
      }
      return info.compactMapValues { $0 as? String }
    #else
      return nil
    #endif
  }

  var remindersStoresPath: String {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Group Containers/group.com.apple.reminders/Container_v1/Stores").path
  }

  func remindersStoresExist() -> Bool {
    FileManager.default.fileExists(atPath: remindersStoresPath)
  }

  /// Reading this directory needs Full Disk Access for the terminal app, like remi's database layer.
  func remindersDatabaseFiles() throws -> [String] {
    guard remindersStoresExist() else {
      throw RemiCommandError(.dbNotFound, "Reminders data directory not found at \(remindersStoresPath)")
    }
    let names: [String]
    do {
      names = try FileManager.default.contentsOfDirectory(atPath: remindersStoresPath)
    } catch {
      throw RemiCommandError(.permissionDenied, "Cannot access Reminders database — permission denied")
    }
    return names.filter { $0.hasSuffix(".sqlite") && !$0.contains("-wal") && !$0.contains("-shm") }.sorted()
      .map { remindersStoresPath + "/" + $0 }
  }

  func open(_ url: String) -> Bool {
    #if os(macOS)
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      process.arguments = [url]
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
