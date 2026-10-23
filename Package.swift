// swift-tools-version: 6.2
// Swift port of remi (https://github.com/mattheworiordan/remi) by Matthew O'Riordan, MIT License.

import PackageDescription

let package = Package(
  name: "reminders",
  platforms: [
    // remi targets macOS only; Linux builds are for development and CI of the pure-logic core.
    .macOS(.v26)
  ],
  products: [
    .executable(name: "remi", targets: ["RemiCLI"]),
    .library(name: "RemiCore", targets: ["RemiCore"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2")
  ],
  targets: [
    // Pure, platform-independent logic: parsing, matching, formatting, sync bookkeeping.
    .target(name: "RemiCore"),
    // Apple-only integrations (EventKit, private ReminderKit, Reminders SQLite store).
    // Everything inside is guarded by `#if canImport(EventKit)` so the package still builds on Linux.
    .target(
      name: "RemiApple",
      dependencies: ["RemiCore"]
    ),
    .executableTarget(
      name: "RemiCLI",
      dependencies: [
        "RemiCore",
        "RemiApple",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(
      name: "RemiCoreTests",
      dependencies: ["RemiCore"]
    ),
  ]
)
