import Foundation
import RemindersCore

#if os(macOS)
  import Darwin
#endif

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

  public func reminderKitProblem() -> String? {
    #if os(macOS)
      RuntimeReminderKit.missingPart()
    #else
      "ReminderKit is only on macOS"
    #endif
  }

  public var hostApplication: HostApplication? {
    #if os(macOS)
      let pid = getpid()
      let tool = ToolProcess(
        pid: pid, executablePath: Self.processRecord(pid)?.executablePath ?? CommandLine.arguments[0],
        responsiblePID: Self.responsiblePID(of: pid), carriesUsageDescription: embeddedInfoPlist != nil)
      return HostApplication.responsible(
        for: tool, lookup: Self.processRecord(_:), displayName: Self.bundleDisplayName(_:),
        declaresRemindersUsage: Self.declaresRemindersUsage(_:))
    #else
      nil
    #endif
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

#if os(macOS)
  extension MacSystemProbe {
    /// The process's parent (via `sysctl(KERN_PROC_PID)`) and executable path (via `proc_pidpath`).
    static func processRecord(_ pid: Int32) -> ProcessRecord? {
      var info = kinfo_proc()
      var size = MemoryLayout<kinfo_proc>.stride
      var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
      guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
      var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
      let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
      guard length > 0 else { return nil }
      let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
      guard let path = String(bytes: bytes, encoding: .utf8) else { return nil }
      return ProcessRecord(pid: pid, parentPID: info.kp_eproc.e_ppid, executablePath: path)
    }

    /// The process macOS attributes `pid`'s privacy permissions to, from libsystem's
    /// `responsibility_get_pid_responsible_for_pid`. It isn't in the SDK headers, so it's looked up at run time;
    /// nil when it's missing or fails.
    static func responsiblePID(of pid: Int32) -> Int32? {
      typealias Responsible = @convention(c) (pid_t) -> pid_t
      guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
      else { return nil }
      let responsible = unsafeBitCast(symbol, to: Responsible.self)(pid)
      return responsible > 0 ? responsible : nil
    }

    /// Whether the app declares why it uses Reminders, without which macOS never asks about it.
    static func declaresRemindersUsage(_ path: String) -> Bool {
      let info = Bundle(path: path)?.infoDictionary ?? [:]
      return ["NSRemindersFullAccessUsageDescription", "NSRemindersUsageDescription"].contains { info[$0] != nil }
    }

    /// The bundle's `CFBundleDisplayName` or `CFBundleName`, such as "Visual Studio Code" for `Code.app`.
    static func bundleDisplayName(_ path: String) -> String? {
      guard let bundle = Bundle(path: path) else { return nil }
      let info = bundle.localizedInfoDictionary ?? bundle.infoDictionary ?? [:]
      return (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
    }
  }
#endif
