# reminders

A Swift port of [remi](https://github.com/mattheworiordan/remi), the fast, reliable CLI and MCP server for
Apple Reminders with section support and iCloud sync. The goal is a single native `remi` binary with the same
commands, flags, `--json` output and `--mcp` server mode as the original TypeScript tool, without Node.js or
helper binaries.

> **Status: foundation.** The pure-logic core is ported and tested. Commands that talk to Reminders
> (EventKit, ReminderKit, the Reminders database) are wired up in follow-up PRs and currently return a
> structured "not implemented yet" error.

## Porting status

| Area | remi source | Swift | Status |
| --- | --- | --- | --- |
| Error codes and errors | `src/core/errors.ts` | `RemiCore/Errors.swift` | ✅ ported |
| Types and `--json` shapes | `src/types.ts` | `RemiCore/Types.swift`, `JSON.swift` | ✅ ported |
| Fuzzy list and section matching | `src/core/fuzzy.ts` | `RemiCore/Fuzzy.swift` | ✅ ported |
| Reminder lookup by title or `--id` | `src/core/lookup.ts` | `RemiCore/Lookup.swift` | ✅ matching ported (fetching pending) |
| Natural-language dates | `src/core/dateparse.ts` (chrono-node) | `RemiCore/DateParse.swift` | ✅ ported, see [deviations](#deviations-from-remi) |
| `--repeat` rules | `src/core/recurrence.ts` | `RemiCore/Recurrence.swift` | ✅ ported |
| Token map (CRDT vector clocks) | `src/core/tokenmap.ts`, `section-helper.swift` | `RemiCore/TokenMap.swift` | ✅ ported |
| Membership checksum (SHA-512) | `src/core/checksum.ts` | `RemiCore/Checksum.swift` | ✅ ported |
| Section membership edits | `src/core/membership.ts` | `RemiCore/Membership.swift` | ✅ blob logic ported (DB I/O pending) |
| Human and JSON output | `src/cli/output.ts` | `RemiCore/Output.swift`, `Style.swift` | ✅ ported, byte-identical |
| CLI surface (commands, aliases, flags) | `src/cli/index.ts` | `RemiCLI` | ✅ parsing, `completions`; the rest pending |
| EventKit layer | `src/core/eventkit.ts`, `reminders-helper.swift` | `RemiApple` | ⏳ next |
| ReminderKit (sections, sync trigger) | `src/core/reminderkit.ts`, `section-helper.swift` | `RemiApple` | ⏳ planned |
| Reminders SQLite store | `src/core/sqlite.ts`, `section-helper.swift` | `RemiApple` | ⏳ planned |
| Commands, `doctor`, `authorize`, `demo` | `src/cli/commands/*` | `RemiCLI` | ⏳ planned |
| MCP server (`remi --mcp`) | `src/mcp/server.ts` | — | ⏳ planned |

## Requirements

- macOS 26 or later to use it (Apple Reminders). Linux builds the pure-logic core and the CLI shell for
  development and CI only.
- Swift 6.4.1 and SwiftLint 0.65.1, pinned in [`mise.toml`](mise.toml). Install [mise](https://mise.jdx.dev), then
  run `mise install`. On a Mac you can also use Xcode 26's Swift 6.x toolchain.
- Formatting uses Apple's [swift-format](https://github.com/swiftlang/swift-format) (`swift format`), which ships
  with the toolchain, so the Swift pin also pins the formatter. Its config is [`.swift-format`](.swift-format).
  [`.swiftlint.yml`](.swiftlint.yml) turns off the SwiftLint style rules that would conflict with it.

## Build and run

```sh
git clone https://github.com/neo-the-on3/reminders && cd reminders
mise install                     # Swift 6.4.1 (optional on a Mac with Xcode 26)
swift build -c release --product remi
.build/release/remi --help
.build/release/remi --version
```

Each PR's macOS CI run also uploads a `remi-macos` build as an artifact.

### Tasks

```sh
mise run build     # swift build
mise run release   # swift build -c release --product remi
mise run test      # swift test
mise run lint      # swift-format lint --strict + SwiftLint --strict (fails on any violation)
mise run format    # swift format --in-place
```

## Package layout

- **`RemiCore`**: pure, platform-independent logic. No Apple frameworks, so it builds and is tested on Linux.
- **`RemiApple`**: Apple-only integrations. Everything is guarded by `#if canImport(EventKit)`.
- **`RemiCLI`**: the `remi` executable (swift-argument-parser).
- **`RemiCoreTests`**: Swift Testing port of remi's `tests/unit/*.test.ts`, plus parity suites.

## Testing

`swift test` runs the ported remi unit tests (checksum, dateparse, output, recurrence, tokenmap) and these
parity suites:

- **Dates**: 1,062 cases generated from chrono-node 2.9 (the parser remi uses), across six reference instants.
  To regenerate them, run [`scripts/chrono-fixtures.mjs`](scripts/chrono-fixtures.mjs) from a remi checkout.
- **Output**: remi's own `output.ts` renders the same sample data with colour off and on, in human and JSON
  modes, verbose and not. The Swift output must match byte for byte. To regenerate, run
  [`scripts/output-fixtures.mts`](scripts/output-fixtures.mts).

Run `mise run format` after regenerating fixtures. SwiftLint skips the generated fixture files.

remi's integration tests need a real Reminders permission grant (and Full Disk Access for sections), which CI
runners can't provide. They will be run by hand on a Mac once the Apple layers land.

## Deviations from remi

These differences are intentional. Each one is covered by a test.

- **Dates.** There is no chrono-node for Swift. `DateParse.swift` implements the English phrases remi
  documents and the ones people commonly type: `today`, `tomorrow`, `tonight`, weekdays with
  `this`/`next`/`last`, `in 3 days`, `2 weeks from now`, `3 days ago`, `next month`, `April 15`, `15 Apr 2027`,
  `4/15`, `12/25/2027`, ISO date-times, and times such as `tomorrow 9am` or `5pm friday`. It reproduces
  chrono's forward-date rules. Other phrases chrono understands may be rejected with `INVALID_ARGUMENT`.
  On purpose: `day after tomorrow` means +2 days (chrono returns +1), `tues` is accepted, `this week` is
  rejected, and `secs` is accepted as seconds.
- **`serializeTokenMap`.** remi passes an array replacer to `JSON.stringify`, which also strips the nested
  `counter`/`modificationTime` fields. The helper is unused upstream, and the port keeps the fields.
- **Corrupt membership data.** remi would crash on an unparseable membership blob. The port reports it as a
  remi error and leaves the blob alone.
- **`--version`** prints the upstream package version (`0.2.1`). remi's CLI hard-codes `0.1.0`.

## Attribution

This project is a port of **remi** by **Matthew O'Riordan**, released under the MIT License. The original
copyright notice is kept in [LICENSE](LICENSE). The behaviour, the reverse-engineered details of Apple
Reminders' sync (see remi's `docs/TECHNICAL_DESIGN.md` and `docs/APPLE_REMINDERS_INTERNALS.md`), and the test
cases all come from remi.
