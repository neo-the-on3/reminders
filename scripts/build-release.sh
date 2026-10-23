#!/usr/bin/env bash
# Builds the release `reminders` binary and, on macOS, ad-hoc signs it and checks its embedded Info.plist.
#
# Usage: scripts/build-release.sh [--universal] [--version <version>] [copy-to-path]
#   --universal          macOS only: build arm64 and x86_64 and merge them with lipo.
#   --version <version>  stamp this version (such as 0.1.0-alpha.1) into `reminders --version` and the
#                        embedded Info.plist. The sources are restored afterwards.
# Prints the path of the binary (or of the copy).
#
# The linker embeds Support/Info.plist (see Package.swift); without it macOS won't show the Reminders prompt.
# Signing with a fixed identifier gives the binary a stable code identity across rebuilds.
set -euo pipefail

cd "$(dirname "$0")/.."
identifier="io.github.neo-the-on3.reminders"
product_info="Sources/RemindersCore/ProductInfo.swift"
info_plist="Support/Info.plist"

universal=false
version=""
copy_to=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --universal) universal=true ;;
    --version)
      version=${2:?--version needs a value}
      shift
      ;;
    -*)
      echo "error: unknown option $1" >&2
      exit 64
      ;;
    *) copy_to=$1 ;;
  esac
  shift
done

if [[ -n $version ]]; then
  if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    echo "error: version must be SemVer, such as 1.2.3 or 0.1.0-alpha.1 (got $version)" >&2
    exit 64
  fi
  # Stamp the version for this build only; the trap puts the committed files back.
  backup=$(mktemp -d)
  cp "$product_info" "$info_plist" "$backup/"
  trap 'cp "$backup/ProductInfo.swift" "$product_info"; cp "$backup/Info.plist" "$info_plist"; rm -rf "$backup"' EXIT
  sed -i.bak -E "s/(public static let version = )\"[^\"]*\"/\1\"$version\"/" "$product_info"
  # CFBundleVersion must be numbers and dots, so it gets the version without its pre-release suffix.
  perl -0pi -e "s|(<key>CFBundleShortVersionString</key>\s*<string>)[^<]*|\${1}$version|; s|(<key>CFBundleVersion</key>\s*<string>)[^<]*|\${1}${version%%-*}|" "$info_plist"
  rm -f "$product_info.bak"
  grep -q "\"$version\"" "$product_info" || { echo "error: could not stamp $version into $product_info" >&2; exit 1; }
fi

if $universal; then
  [[ "$(uname)" == "Darwin" ]] || { echo "error: --universal needs macOS" >&2; exit 64; }
  mkdir -p .build/universal
  slices=()
  for arch in arm64 x86_64; do
    swift build -c release --product reminders --arch "$arch" >&2
    # Each architecture may build into the same products directory, so keep this slice before the next build.
    cp "$(swift build -c release --arch "$arch" --show-bin-path)/reminders" ".build/universal/reminders-$arch"
    slices+=(".build/universal/reminders-$arch")
  done
  binary=.build/universal/reminders
  lipo -create -output "$binary" "${slices[@]}"
  lipo "$binary" -verify_arch arm64 x86_64
else
  swift build -c release --product reminders >&2
  binary="$(swift build -c release --show-bin-path)/reminders"
fi

if [[ "$(uname)" == "Darwin" ]]; then
  codesign --force --sign - --identifier "$identifier" "$binary" >&2
  codesign --verify --strict "$binary" >&2
  plist=$(launchctl plist __TEXT,__info_plist "$binary")
  if ! grep -q NSRemindersFullAccessUsageDescription <<<"$plist"; then
    echo "error: $binary has no embedded Info.plist with NSRemindersFullAccessUsageDescription" >&2
    exit 1
  fi
  if [[ -n $version ]] && ! grep -q "$version" <<<"$plist"; then
    echo "error: the Info.plist embedded in $binary doesn't carry version $version" >&2
    exit 1
  fi
fi

if [[ -n $copy_to ]]; then
  mkdir -p "$(dirname "$copy_to")"
  cp "$binary" "$copy_to"
  echo "$copy_to"
else
  echo "$binary"
fi
