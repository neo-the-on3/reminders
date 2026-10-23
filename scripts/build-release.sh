#!/usr/bin/env bash
# Builds the release `reminders` binary and, on macOS, ad-hoc signs it and checks its embedded Info.plist.
#
# Usage: scripts/build-release.sh [copy-to-path]
# Prints the path of the binary (or of the copy).
#
# The linker embeds Support/Info.plist (see Package.swift); without it macOS won't show the Reminders prompt.
# Signing with a fixed identifier gives the binary a stable code identity across rebuilds.
set -euo pipefail

cd "$(dirname "$0")/.."
identifier="io.github.neo-the-on3.reminders"

swift build -c release --product reminders >&2
binary="$(swift build -c release --show-bin-path)/reminders"

if [[ "$(uname)" == "Darwin" ]]; then
  codesign --force --sign - --identifier "$identifier" "$binary" >&2
  codesign --verify --strict "$binary" >&2
  if ! launchctl plist __TEXT,__info_plist "$binary" | grep -q NSRemindersFullAccessUsageDescription; then
    echo "error: $binary has no embedded Info.plist with NSRemindersFullAccessUsageDescription" >&2
    exit 1
  fi
fi

if [[ $# -gt 0 ]]; then
  cp "$binary" "$1"
  echo "$1"
else
  echo "$binary"
fi
