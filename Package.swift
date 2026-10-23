// swift-tools-version: 6.2
// reminders: a native Swift CLI for Apple Reminders. See README.md for the package layout.

import PackageDescription

let package = Package(
  name: "reminders",
  platforms: [
    // Apple Reminders features need macOS 26. Linux builds the platform-independent core for development and CI.
    .macOS(.v26)
  ],
  products: [
    .executable(name: "reminders", targets: ["RemindersCLI"]),
    .library(name: "RemindersCore", targets: ["RemindersCore"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2")
  ],
  targets: [
    // Domain model, the store protocol, commands as a service, parsing, matching, presentation and section-sync
    // bookkeeping. Foundation only.
    .target(name: "RemindersCore"),
    // The platform: EventKit and the Mac's system facts. Compiles everywhere; off macOS the store reports
    // UNSUPPORTED_PLATFORM.
    .target(name: "RemindersApple", dependencies: ["RemindersCore"]),
    .executableTarget(
      name: "RemindersCLI",
      dependencies: [
        "RemindersCore",
        "RemindersApple",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(name: "RemindersCoreTests", dependencies: ["RemindersCore"]),
    .testTarget(name: "RemindersCLITests", dependencies: ["RemindersCLI", "RemindersCore"]),
  ],
  swiftLanguageModes: [.v6]
)
