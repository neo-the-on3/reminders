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
    .library(name: "RemiCore", targets: ["RemiCore"])
  ],
  targets: [
    // Pure, platform-independent logic: parsing, matching, formatting, sync bookkeeping.
    .target(name: "RemiCore")
  ]
)
