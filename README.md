# reminders

A Swift port of [remi](https://github.com/mattheworiordan/remi), the fast, reliable CLI and MCP server for
Apple Reminders with section support and iCloud sync. The goal is a single native `remi` binary with the same
commands, flags, `--json` output and `--mcp` server mode as the original TypeScript tool, without Node.js or
helper binaries.

> **Status: EventKit commands.** The pure-logic core and the EventKit layer are ported: `lists`, `list`, `add`,
> `complete`, `update`, `delete`, `today`, `overdue`, `upcoming`, `search`, `create-list`, `delete-list`,
> `authorize`, `doctor` and `completions` work. Section commands (ReminderKit and the Reminders database), `demo`
> and `--mcp` come in follow-up PRs and currently return a structured "not implemented yet" error.

## Porting status

| Area | remi source | Swift | Status |
| --- | --- | --- | --- |
| Error codes and errors | `src/core/errors.ts` | `RemiCore/Errors.swift` | ✅ ported |
| Types and `--json` shapes | `src/types.ts` | `RemiCore/Types.swift`, `JSON.swift` | ✅ ported |
| Fuzzy list and section matching | `src/core/fuzzy.ts` | `RemiCore/Fuzzy.swift` | ✅ ported |
| Reminder lookup by title or `--id` | `src/core/lookup.ts`, `src/core/resolve.ts` | `RemiCore/Lookup.swift`, `Commands.swift` | ✅ ported |
| Natural-language dates | `src/core/dateparse.ts` (chrono-node) | `RemiCore/DateParse.swift` | ✅ ported, see [deviations](#deviations-from-remi) |
| `--repeat` rules | `src/core/recurrence.ts` | `RemiCore/Recurrence.swift` | ✅ ported |
| Token map (CRDT vector clocks) | `src/core/tokenmap.ts`, `section-helper.swift` | `RemiCore/TokenMap.swift` | ✅ ported |
| Membership checksum (SHA-512) | `src/core/checksum.ts` | `RemiCore/Checksum.swift` | ✅ ported |
| Section membership edits | `src/core/membership.ts` | `RemiCore/Membership.swift` | ✅ blob logic ported (DB I/O pending) |
| Human and JSON output | `src/cli/output.ts` | `RemiCore/Output.swift`, `Style.swift` | ✅ ported, byte-identical |
| CLI surface (commands, aliases, flags) | `src/cli/index.ts` | `RemiCLI` | ✅ ported |
| EventKit layer | `src/core/eventkit.ts`, `reminders-helper.swift` | `RemiCore/ReminderStore.swift`, `ReminderFilters.swift`, `RemiApple/EventKitStore.swift` | ✅ ported |
| ReminderKit (sections, sync trigger) | `src/core/reminderkit.ts`, `section-helper.swift` | `RemiApple` | ⏳ planned |
| Reminders SQLite store | `src/core/sqlite.ts`, `section-helper.swift` | `RemiApple` | ⏳ planned |
| Reminder commands, `doctor`, `authorize` | `src/cli/commands/*` | `RemiCore/Commands.swift`, `Diagnostics.swift` | ✅ ported (no sections yet) |
| Section commands, `add --section`, `demo` | `src/cli/commands/*` | `RemiCLI` | ⏳ planned |
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
scripts/build-release.sh         # release build, embedded Info.plist, ad-hoc signed (= mise run release)
.build/release/remi --help
.build/release/remi authorize    # first run: grant Reminders access
.build/release/remi lists
```

Each PR's macOS CI run also uploads the signed `remi-macos` build as an artifact.

## Permissions

remi uses EventKit, so macOS asks for **Reminders** access the first time it runs a Reminders command.

- **The prompt needs an Info.plist.** A command-line tool has no app bundle, so the linker embeds
  [`Support/Info.plist`](Support/Info.plist) into the binary's `__TEXT,__info_plist` section (see the
  `linkerSettings` in [`Package.swift`](Package.swift)). It carries the bundle identifier
  `io.github.neo-the-on3.remi` and `NSRemindersFullAccessUsageDescription`. Without those, macOS refuses to
  prompt. Check a binary with `launchctl plist __TEXT,__info_plist .build/release/remi`; `remi doctor` reports it
  too.
- **Signing.** [`scripts/build-release.sh`](scripts/build-release.sh) ad-hoc signs the binary with that
  identifier (`codesign -s - -i io.github.neo-the-on3.remi`), so it has a stable code identity. No Apple
  Developer certificate is needed to run it on your own Mac. A binary downloaded from CI gets the quarantine
  attribute; clear it with `xattr -d com.apple.quarantine remi`.
- **macOS grants access to the terminal app**, not to remi. As with the TypeScript remi, the prompt names
  your terminal (Terminal, iTerm, Cursor, …) and the grant shows up under that app in **System Settings >
  Privacy & Security > Reminders**. Grant it once per terminal app.
- **`remi authorize`** triggers the prompt. If access was refused, it opens the Reminders pane in System
  Settings. It also checks Full Disk Access, which only the (upcoming) section features need, and opens that
  pane if it's missing. **`remi doctor`** shows what's granted without prompting; it exits 1 if a check fails.
- If you denied access by mistake, re-enable your terminal in System Settings, or run
  `tccutil reset Reminders` and start again.

### Tasks

```sh
mise run build     # swift build
mise run release   # scripts/build-release.sh: release build with embedded Info.plist, ad-hoc signed
mise run test      # swift test (unit tests; the integration suite is skipped)
mise run integration  # REMI_INTEGRATION=1 swift test --filter RemiIntegrationTests (macOS, real Reminders)
mise run lint      # swift-format lint --strict + SwiftLint --strict (fails on any violation)
mise run format    # swift format --in-place
```

## Package layout

- **`RemiCore`**: pure, platform-independent logic. No Apple frameworks, so it builds and is tested on Linux.
- **`RemiApple`**: Apple-only integrations. Everything is guarded by `#if canImport(EventKit)`.
- **`RemiCLI`**: the `remi` executable (swift-argument-parser).
- **`RemiCoreTests`**: Swift Testing port of remi's `tests/unit/*.test.ts`, parity suites, and command tests
  against an in-memory `ReminderStore`.
- **`RemiIntegrationTests`**: opt-in port of remi's `tests/integration/crud.test.ts`.

Command logic lives in `RemiCore` and talks to Reminders only through the `ReminderStore` protocol. `RemiApple`
implements it with EventKit; the unit tests use a fake with the same semantics.

## Testing

`swift test` runs the ported remi unit tests (checksum, dateparse, output, recurrence, tokenmap) and these
parity suites:

- **Dates**: 1,062 cases generated from chrono-node 2.9 (the parser remi uses), across six reference instants.
  To regenerate them, run [`scripts/chrono-fixtures.mjs`](scripts/chrono-fixtures.mjs) from a remi checkout.
- **Output**: remi's own `output.ts` renders the same sample data with colour off and on, in human and JSON
  modes, verbose and not. The Swift output must match byte for byte. To regenerate, run
  [`scripts/output-fixtures.mts`](scripts/output-fixtures.mts).

Run `mise run format` after regenerating fixtures. SwiftLint skips the generated fixture files.

The command tests run every ported command against `FakeReminderStore`, an in-memory store with EventKit's
semantics, including remi's CRUD integration scenario.

### Integration tests (on a Mac)

`Tests/RemiIntegrationTests` ports remi's `tests/integration/crud.test.ts`. It runs the built `remi` with
`--json` against a throwaway list named `_remi_test_<hex>`, deletes it at the end, and first removes lists left
behind by an interrupted run. It needs Reminders access, which CI runners can't grant, so it only runs when
`REMI_INTEGRATION=1`:

```sh
swift build && .build/debug/remi authorize   # grant access for this terminal once
mise run integration                          # = REMI_INTEGRATION=1 swift test --filter RemiIntegrationTests
REMI_BINARY=.build/release/remi mise run integration   # test the signed release build instead
```

The section integration tests (`tests/integration/sections.test.ts`) arrive with the sections layer.

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
- **Errors from Reminders operations.** remi maps the helper's error text to codes by substring (any
  "not found" becomes `LIST_NOT_FOUND`, anything else `SWIFT_EXECUTION_FAILED`). The port raises the proper code:
  `PERMISSION_DENIED` (same message and suggestion as remi), `LIST_NOT_FOUND`, `REMINDER_NOT_FOUND` (for example
  when updating a reminder that is already completed), and `SWIFT_EXECUTION_FAILED` for EventKit save failures.
- **Impossible due dates.** remi's helper silently drops a due date it can't read (`--due 2026-02-30`); the port
  rejects it with `INVALID_ARGUMENT`.
- **`add --section`** fails with `REMINDERKIT_UNAVAILABLE` and creates nothing, until sections are ported.
  `list --section` is accepted and ignored, as in remi.
- **`doctor`** never shows the permission prompt (remi's does, and then waits for an answer). If access hasn't
  been requested yet it reports "Not requested yet" and points to `remi authorize`. It requires macOS 26
  (remi: 13). It replaces remi's "Swift" and "reminders-helper" checks, which
  don't apply to a single native binary, with an "Info.plist" check. Its "Reminders database" check only
  confirms that the stores directory is readable (Full Disk Access) and lists a `.sqlite` file; it doesn't open
  the database yet. `doctor --db` reports a warning until the database layer lands.
- **`--version`** prints the upstream package version (`0.2.1`). remi's CLI hard-codes `0.1.0`.

## Attribution

This project is a port of **remi** by **Matthew O'Riordan**, released under the MIT License. The original
copyright notice is kept in [LICENSE](LICENSE). The behaviour, the reverse-engineered details of Apple
Reminders' sync (see remi's `docs/TECHNICAL_DESIGN.md` and `docs/APPLE_REMINDERS_INTERNALS.md`), and the test
cases all come from remi.
