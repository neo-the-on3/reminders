#!/usr/bin/env bash
# Build a release remi for macOS with its embedded Info.plist, and ad-hoc sign it.
#
# Usage: scripts/build-release.sh [output-path]   (default: .build/release/remi)
#
# The linker embeds Support/Info.plist (see Package.swift). Signing with the same identifier gives the binary a
# stable code identity, so the Reminders permission macOS records stays attached to it across rebuilds.
set -euo pipefail

cd "$(dirname "$0")/.."
identifier="io.github.neo-the-on3.remi"

swift build -c release --product remi
binary="$(swift build -c release --show-bin-path)/remi"

if [[ "$(uname)" == "Darwin" ]]; then
  codesign --force --sign - --identifier "$identifier" "$binary"
  codesign --verify --verbose "$binary"
  # Fail if the Info.plist didn't make it into the binary
  launchctl plist __TEXT,__info_plist "$binary" | grep -q "NSRemindersFullAccessUsageDescription"
fi

if [[ $# -gt 0 ]]; then
  cp "$binary" "$1"
  echo "$1"
else
  echo "$binary"
fi
