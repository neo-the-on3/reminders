# reminders

A fast, native command-line tool for Apple Reminders, with section support and iCloud sync. One Swift binary,
no Node.js or helper processes, with `--json` output for scripts and (planned) an MCP server mode for AI
assistants.

> **Status: foundation.** The platform-independent core (dates, recurrence, name matching, output, section-sync
> bookkeeping) is done and tested. Commands that talk to Apple Reminders arrive in follow-up PRs; until then they
> fail with a structured `NOT_IMPLEMENTED` error.

## Requirements

- macOS 26 or later to use it. Linux builds and tests the platform-independent core for development and CI.
- Swift 6.4.1 and SwiftLint 0.65.1, pinned in [`mise.toml`](mise.toml). Install [mise](https://mise.jdx.dev),
  then run `mise install`. On a Mac, Xcode 26's Swift 6.x toolchain also works.
- Formatting uses Apple's [swift-format](https://github.com/swiftlang/swift-format) (`swift format`), which ships
  with the toolchain, so the Swift pin also pins the formatter. Its config is [`.swift-format`](.swift-format);
  [`.swiftlint.yml`](.swiftlint.yml) turns off the [SwiftLint](https://github.com/realm/SwiftLint) style rules
  that would conflict with it.

### If `mise install` hangs

mise looks up tool versions on `mise-versions.jdx.dev` first. When that host is unreachable (some networks block
it), `mise install` can hang or time out. Tell mise to ask the tools' own release sources instead:

```sh
MISE_USE_VERSIONS_HOST=0 mise install
```

To make that permanent: `mise settings use_versions_host=false`.

## Build and run

```sh
git clone https://github.com/neo-the-on3/reminders && cd reminders
mise install                      # or MISE_USE_VERSIONS_HOST=0 mise install
swift build -c release --product reminders
.build/release/reminders --help
```

Each CI run on macOS uploads the release binary as the `reminders-macos` artifact.

### Shell completions

```sh
# zsh: either source it (works before or after compinit)…
source <(reminders completions zsh)
# …or install it on your fpath, before compinit runs
reminders completions zsh > "${fpath[1]}/_reminders"

# bash
source <(reminders completions bash)

# fish
reminders completions fish > ~/.config/fish/completions/reminders.fish
```

Completions cover every command and alias (`ls`, `done`, `rm`), and each command's flags and options.

### Tasks

```sh
mise run build     # swift build
mise run release   # swift build -c release --product reminders
mise run test      # swift test
mise run lint      # swift format lint --strict + swiftlint --strict (fails on any violation)
mise run format    # swift format --in-place
```

## Design

Three targets with one-way dependencies:

- **`RemindersCore`**: the platform-independent core, Foundation only, so it builds and is tested on Linux.
  - `Model/`: value types. `Reminder`, `ReminderList`, `Section`, `Priority`, `CalendarDay` (a time-zone-free
    `YYYY-MM-DD` day) and `Recurrence` (parsed from `--repeat`, described back as `every 2 weeks`).
  - `Dates/`: `DayClock` (injected "now" and time zone) and `DueDateParser` (`YYYY-MM-DD` or English such as
    `next friday`, `in 3 days`, `12/25`).
  - `Matching/`: forgiving name lookup (`exact > case-insensitive > unique substring`) as `Collection` extensions:
    `lists.resolve("groc")`, `reminders.find(title:idPrefix:inList:)`.
  - `Presentation/`: `Console` sends any `ConsoleRepresentable` result (`ListOverview`, `ReminderListing`,
    `Confirmation`, …) either to `TextRenderer` or, with `--json`, through `JSONEncoder` into a
    `{"success": true, "data": …}` envelope; failures become `{"success": false, "error": …}`.
  - `SectionSync/`: what Reminders stores for sections: `SectionMemberships` (with its SHA-512 checksum) and
    `ResolutionTokenMap` (the vector clocks that make iCloud push a change). They edit stored JSON in place, keeping
    unknown fields, key order and number formatting, because Reminders checksums the exact bytes.
  - `RemindersError`: one error type with stable machine-readable codes; core APIs use typed throws.
- **`RemindersCLI`**: the `reminders` executable, built on swift-argument-parser's `AsyncParsableCommand`. Each
  command conforms to `ConsoleCommand`, which renders results and errors consistently and maps failures to exit
  status 1 (usage errors exit 64).
- **Tests**: Swift Testing suites for both targets.

## Testing

`swift test` runs everything. Two suites compare against references:

- **Dates**: 1,062 cases across six reference instants, generated from chrono-node 2.9, a mature JavaScript
  natural-language date parser. To regenerate them, run
  [`scripts/date-reference-cases.mjs`](scripts/date-reference-cases.mjs) (instructions inside).
- **Text output**: the human-readable output for a fixed sample, with colour off and on and verbose or not, must
  match [`RenderingFixtures.swift`](Tests/RemindersCoreTests/RenderingFixtures.swift) byte for byte.

The completion tests also syntax-check each generated script with `bash -n`, `zsh -n` and `fish -n` when those
shells are installed.

## Behaviour notes

The CLI contract (commands, aliases, arguments, flags, error codes and the JSON shapes) follows the original
tool. Intentional differences:

- **JSON formatting.** `--json` output is produced by `JSONEncoder`: pretty-printed with sorted keys, so objects
  print as `"key" : value` and the envelope's `data` comes before `success`. The values and structure are the same.
- **Dates.** `DueDateParser` covers the phrases people commonly type: `today`, `tomorrow`, `tonight`, weekdays with
  `this`/`next`/`last`, `in 3 days`, `2 weeks from now`, `3 days ago`, `next month`, `April 15`, `15 Apr 2027`,
  `4/15`, `12/25/2027`, ISO date-times, and times such as `tomorrow 9am` or `5pm friday`. Other phrases are
  rejected with `INVALID_ARGUMENT`. Compared with the reference parser, `day after tomorrow` means +2 days,
  `tues` is accepted, `this week` is rejected, and impossible dates such as `2026-02-30` are rejected instead of
  being passed through.
- **Usage errors exit 64.** A non-numeric `upcoming --days`, an unknown `--priority`, or an unsupported shell for
  `completions` is reported by the argument parser with exit status 64.
- **Error codes.** Unknown sections report `SECTION_NOT_FOUND` (not `LIST_NOT_FOUND`). Unported commands report
  `NOT_IMPLEMENTED`. Store failures will report `STORE_FAILURE`, and running Reminders commands on a platform
  without Apple Reminders `UNSUPPORTED_PLATFORM`.
- **Text matching** follows Swift string semantics: canonically equivalent names match (`é` typed either way),
  and table columns are measured in terminal cells, so wide characters line up.
- **Corrupt section data** is reported as an error and never overwritten.
- **`demo`** is hidden from help and completions until it is implemented.

## Attribution

This project is a Swift rewrite of [remi](https://github.com/mattheworiordan/remi) by Matthew O'Riordan, released
under the MIT License; its copyright notice is kept in [LICENSE](LICENSE). The command set, the behaviour, and the
knowledge of how Apple Reminders stores and syncs sections come from that project.
