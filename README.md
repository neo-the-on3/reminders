# reminders

A fast, native command-line tool for Apple Reminders, with section support and iCloud sync. One Swift binary,
no Node.js or helper processes, with `--json` output for scripts and an MCP server mode (`reminders --mcp`) for AI
assistants.

> **Status: lists and reminders work; sections are next.** `lists`, `list`, `today`, `overdue`, `upcoming`,
> `search`, `add`, `complete`, `update`, `delete`, `create-list`, `delete-list`, `authorize` and `doctor` work
> against Apple Reminders through EventKit, from the command line and as MCP tools; `setup-claude`,
> `setup-claude-code` and `setup-cursor` register the MCP server with those clients. Section commands, tools and
> `--section` options, and `demo`, arrive in follow-up PRs; until then they fail with a structured
> `NOT_IMPLEMENTED` error.

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

## Install

```sh
brew install neo-the-on3/tap/reminders
reminders authorize
```

This is an **alpha** pre-release: lists and reminders work, sections don't yet (see the status above). It needs
macOS 26 or later and runs natively on Apple silicon and Intel (a universal binary).

- The binary is **ad-hoc signed, not notarized**. Homebrew doesn't quarantine what it downloads, so macOS runs it
  without a Gatekeeper prompt. A copy downloaded by a browser may be blocked; remove the quarantine flag with
  `xattr -d com.apple.quarantine reminders`.
- The **first run asks for Reminders access**. Run under an MCP client such as Claude Desktop, the prompt and
  the System Settings entry say `reminders`. Run from Terminal, they name the terminal app (see
  [Reminders permission](#reminders-permission)). `reminders authorize` triggers the prompt on purpose.
- To use it from an MCP client, run `reminders setup-claude`, `reminders setup-claude-code` or
  `reminders setup-cursor` (see [MCP server](#mcp-server)). They register the stable
  `$(brew --prefix)/opt/reminders/bin/reminders`, so upgrades don't break the client's config.

Releases are built by [`.github/workflows/release.yml`](.github/workflows/release.yml) from `v*` tags. Each one
has `reminders-<version>-macos-universal.tar.gz` (the binary, LICENSE and README) and its `.sha256`. The formula
lives in [neo-the-on3/homebrew-tap](https://github.com/neo-the-on3/homebrew-tap).

## Build and run

```sh
git clone https://github.com/neo-the-on3/reminders && cd reminders
mise install                      # or MISE_USE_VERSIONS_HOST=0 mise install
scripts/build-release.sh          # prints .build/release/reminders
.build/release/reminders authorize
.build/release/reminders lists
```

Each CI run on macOS uploads the signed release binary as the `reminders-macos` artifact.
`scripts/build-release.sh --universal --version 1.2.3` builds the release binary for both architectures and stamps
the version into `reminders --version` and the embedded Info.plist, leaving the sources unchanged afterwards.
Without `--version`, builds report the development version, `0.1.0-dev`.

### Reminders permission

macOS grants Reminders access to the process responsible for `reminders`. From Terminal, iTerm or Cursor
that's the app, so the prompt names it and the permission is shared by everything you run there. An app that
doesn't take responsibility for what it starts, such as Claude Desktop for its MCP servers, leaves `reminders`
responsible for itself: the prompt then names `reminders`, and it appears under that name in System Settings.
`reminders authorize` triggers the prompt and opens System Settings for anything still missing;
`reminders doctor` checks everything without prompting. Any other command asks the first time too. Both name
what macOS asks about. They ask macOS for the responsible process; if that isn't available they infer it: an app
that declares no Reminders usage description can't be asked, so `reminders` (which embeds one) is named instead
of it.

macOS only asks once. After access is denied, restricted or set to write-only, re-running `authorize` shows no
prompt: enable the app (or `reminders`) under System Settings › Privacy & Security › Reminders (choose Full
Access), then restart that app, or just run `reminders` again. `doctor`, `authorize` and every `PERMISSION_DENIED` error say which of these states applies.

macOS only prompts a command-line tool that carries a usage description, so the linker embeds
[`Support/Info.plist`](Support/Info.plist) (bundle identifier `io.github.neo-the-on3.reminders` and
`NSRemindersFullAccessUsageDescription`) as the binary's `__TEXT,__info_plist` section.
[`scripts/build-release.sh`](scripts/build-release.sh) also ad-hoc signs the binary with that identifier and
fails if the plist is missing. Check a binary with:

```sh
launchctl plist __TEXT,__info_plist .build/release/reminders
codesign -dv .build/release/reminders     # Identifier=io.github.neo-the-on3.reminders, Signature=adhoc
```

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
mise run release   # scripts/build-release.sh (signed on macOS)
mise run test      # swift test
mise run integration  # Apple Reminders integration tests (macOS, see Testing)
mise run lint      # swift format lint --strict + swiftlint --strict (fails on any violation)
mise run format    # swift format --in-place
```

## MCP server

`reminders --mcp` runs a [Model Context Protocol](https://modelcontextprotocol.io) server on stdin/stdout, so AI
assistants can manage reminders without shell access. Point your client at the binary with an **absolute path**,
because desktop apps don't see your shell's `PATH`.

### Setting up a client

These commands register a server named `reminders` that runs this binary with `--mcp`:

```sh
reminders setup-claude                    # Claude Desktop
reminders setup-claude-code               # Claude Code, user scope (--scope local|project for this directory)
reminders setup-cursor                    # Cursor, every project (--project <dir> for one project)
```

- **Path.** The command is the running binary's absolute path with symlinks resolved. For a Homebrew install,
  which lives in a versioned `Cellar` directory that upgrades delete, it's
  `$(brew --prefix)/opt/reminders/bin/reminders` instead (or `$(brew --prefix)/bin/reminders`).
- **Merging.** Claude Desktop's `~/Library/Application Support/Claude/claude_desktop_config.json` and Cursor's
  `~/.cursor/mcp.json` (or `<dir>/.cursor/mcp.json`) are edited in place. Only the `reminders` entry's text
  changes: everything else (other servers and settings, their order, spacing, one-line objects, line endings) is
  kept byte for byte, so `--remove` after adding gives back the original file. A new entry is laid out like its
  neighbours, using the file's indentation. The file and its folder are created when missing. Before a change the
  original is copied to `<file>.bak-<YYYYMMDD-HHMMSS>`, and the new file is written atomically. A file that isn't
  valid JSON is left alone and reported with its line and column (`CONFIG_INVALID`).
- **Claude Code** owns its config, so `setup-claude-code` runs
  `claude mcp add --transport stdio --scope user reminders -- <binary> --mcp`. Without `claude` on `PATH` it prints
  that command instead.
- **Running it again** changes nothing when the same server is registered. A different `reminders` server is
  reported (`CONFIG_CONFLICT`) and replaced only with `--force`.
- **`--dry-run`** shows the change (the new file, or the `claude` commands) without making it; **`--remove`**
  takes the server out again (a different one only with `--force`); **`--json`** reports what happened as
  `{"outcome": "added" | "replaced" | "unchanged" | "removed" | "absent" | "manual", "configPath", "backupPath", …}`.
- Each command ends with the next step (restart Claude Desktop, start a new Claude Code session, restart Cursor)
  and a note on the Reminders permission prompt for that app: Claude Desktop's names `reminders`, Cursor's names
  Cursor, and Claude Code's names the app it runs in (see **Permission** below). `setup-claude` and `setup-cursor` take
  `--config <file>` to edit another file, for testing.

### Configuring a client by hand

**Claude Desktop**: edit `~/Library/Application Support/Claude/claude_desktop_config.json` (Settings ›
Developer › Edit Config), then restart Claude:

```json
{
  "mcpServers": {
    "reminders": {
      "command": "/usr/local/bin/reminders",
      "args": ["--mcp"]
    }
  }
}
```

**Claude Code**: `claude mcp add --transport stdio --scope user reminders -- /usr/local/bin/reminders --mcp`

**Cursor**: add the same `mcpServers` entry, with `"type": "stdio"`, to `~/.cursor/mcp.json` (or
`.cursor/mcp.json` in a project).

**Other clients** (VS Code, Zed, Windsurf, …): register a stdio server whose command is the binary and whose only
argument is `--mcp`.

**Try it without a client** using the MCP Inspector (needs Node.js) or the bundled script:

```sh
npx @modelcontextprotocol/inspector "$(scripts/build-release.sh)" --mcp
scripts/mcp-session.sh .build/release/reminders reminders_lists '{}' reminders_today '{}'
```

**Permission.** macOS assigns Reminders access to the server's responsible process. Claude Desktop leaves that
to the server, so the prompt names `reminders` itself; clients that take responsibility get the prompt in their
own name: Cursor, or for Claude Code the terminal app it runs in. If tools report `PERMISSION_DENIED`, the error names
whichever it is: allow it under System Settings › Privacy & Security › Reminders, then restart the client. A
client that can't show the prompt gets an error saying macOS didn't show it.

### Tools

Each tool runs the same operation as the CLI command, with the same name matching and error codes.

| Tool | Arguments | Result (`structuredContent`) |
| --- | --- | --- |
| `reminders_lists` | — | `{"lists": [list]}` |
| `reminders_list` | `list`, `includeCompleted?` | `{"reminders": [reminder]}` |
| `reminders_today`, `reminders_overdue` | — | `{"reminders": [reminder]}` |
| `reminders_upcoming` | `days?` (default 7; due today through today + N, no overdue) | `{"reminders": [reminder]}` |
| `reminders_search` | `query` | `{"reminders": [reminder]}` |
| `reminders_add` | `list`, `title`, `due?`, `priority?`, `notes?`, `repeat?`, `section?`* | `{"message", "id"}` |
| `reminders_complete` | `list`, `title` or `id` | `{"message"}` |
| `reminders_update` | `list`, `title` or `id`, `newTitle?`, `due?`, `clearDue?`, `priority?`, `notes?` | `{"message"}` |
| `reminders_delete` | `list`, `title` or `id` | `{"message"}` |
| `reminders_create_list` | `name` | `{"message", "id"}` |
| `reminders_delete_list` | `list` | `{"message"}` |
| `reminders_sections`, `reminders_create_section`, `reminders_delete_section`, `reminders_move` | see schema | not implemented yet* |

\* Section tools, and `section` on `reminders_add`, report `NOT_IMPLEMENTED` until sections land.

Every tool publishes a JSON Schema for its input (unknown arguments are rejected) and, except the section tools,
for its output, and carries annotations (`readOnlyHint` on queries, `destructiveHint` on deletions).
Results come back both as `structuredContent` and as the same JSON in a text block. Failures are tool errors
(`isError: true`) whose text is `{"error": {"code", "message", "suggestion"}}` with the CLI's error codes; an
unknown tool name is a JSON-RPC `-32602` error.

## Design

Five targets with one-way dependencies (`RemindersCLI` → `RemindersMCP`, `RemindersApple` → `RemindersCore`):

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
  - `Store/`: the `ReminderStore` protocol (`Sendable`, async, typed throws), which is everything the commands
    need from a reminders database, plus `InMemoryReminderStore`, an actor used by the tests.
  - `Service/`: `RemindersService`, the commands as operations on any store: access checks, list resolution,
    counts, the today/overdue/upcoming/search filters and the changes. It returns `ConsoleRepresentable` values.
  - `Diagnostics/`: `doctor`'s checks and `authorize`'s steps, against a `SystemProbe` (macOS version, embedded
    Info.plist, database directory, opening System Settings).
  - `MCPSetup/`: the setup commands. `MCPConfigDocument` merges the `reminders` entry into a client's
    `mcpServers`, `ConfigFile` backs up and atomically replaces the file, `ExecutableLocation` picks a path that
    survives Homebrew upgrades, and `ClaudeCodeRegistration` builds the `claude mcp` commands, run through a
    `CommandRunner`. Paths come from a `SetupEnvironment` (home, current directory, binary, `PATH`), so all of it
    is tested on Linux in temporary directories.
  - `RemindersError`: one error type with stable machine-readable codes; core APIs use typed throws.
- **`RemindersApple`**: the platform. `EventKitReminderStore` is an actor that owns the `EKEventStore`;
  EventKit objects never leave it (fetches convert to `Reminder` values, changes look items up by identifier).
  `MacSystemProbe` provides the machine facts. It compiles everywhere: off macOS, `UnsupportedPlatformStore`
  answers every call with `UNSUPPORTED_PLATFORM`.
- **`RemindersMCP`**: the MCP server on the official [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)
  (pinned to 0.12.1). `ReminderTool` is an enum of the tools with their schemas and annotations;
  `RemindersToolbox` validates arguments against those schemas (`ToolArguments`) and calls `RemindersService`,
  so the tools share every rule with the CLI. `SerialTransport` hands the server one request at a time, in arrival
  order, so pipelined calls see each other's effects. It also keeps a stdio session open until every request has
  been answered.
- **`RemindersCLI`**: the `reminders` executable, built on swift-argument-parser's `AsyncParsableCommand`. Each
  command conforms to `ConsoleCommand` and runs in a `CommandContext` (console, service, system probe), which
  renders results and errors consistently and maps failures to exit status 1 (usage errors exit 64). Tests run
  commands in a context backed by the in-memory store.
- **Tests**: Swift Testing suites for each target, plus opt-in integration tests.

## Testing

`swift test` runs everything. Two suites compare against references:

- **Dates**: 1,062 cases across six reference instants, generated from chrono-node 2.9, a mature JavaScript
  natural-language date parser. To regenerate them, run
  [`scripts/date-reference-cases.mjs`](scripts/date-reference-cases.mjs) (instructions inside).
- **Text output**: the human-readable output for a fixed sample, with colour off and on and verbose or not, must
  match [`RenderingFixtures.swift`](Tests/RemindersCoreTests/RenderingFixtures.swift) byte for byte.

The completion tests also syntax-check each generated script with `bash -n`, `zsh -n` and `fish -n` when those
shells are installed. Every command is also tested end to end against `InMemoryReminderStore`, and so is every
MCP tool: the MCP tests connect an SDK client to the server over the SDK's in-memory transport (on Linux too) and
check results against the published output schemas.

### Integration tests (macOS)

`RemindersIntegrationTests` drive the `reminders` binary with `--json` against Apple Reminders. They only touch a
throwaway list named `_reminders_test_<hex>`, which they delete afterwards (leftovers from interrupted runs are
removed at the start). They're skipped unless you opt in:

```sh
REMINDERS_INTEGRATION=1 swift test --filter RemindersIntegrationTests   # or: mise run integration
# Test a particular binary, such as the signed release build:
REMINDERS_BINARY="$(scripts/build-release.sh)" REMINDERS_INTEGRATION=1 swift test --filter RemindersIntegrationTests
```

Run `reminders authorize` first: the terminal app needs Reminders access.

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
- **`upcoming` starts today.** `upcoming --days N` (and `reminders_upcoming`) lists incomplete reminders due from
  today through today + N days, both included; `--days 0` is today only. Overdue reminders are left to `overdue`,
  so "what's coming up" never answers with something already late. The original also included everything
  overdue. A negative `--days` is `INVALID_ARGUMENT`.
- **Usage errors exit 64.** A non-numeric `upcoming --days`, an unknown `--priority`, or an unsupported shell for
  `completions` is reported by the argument parser with exit status 64.
- **Error codes.** Unknown sections report `SECTION_NOT_FOUND` (not `LIST_NOT_FOUND`). Unported commands and
  options report `NOT_IMPLEMENTED`, including `list --section` (which the original accepted but ignored). Failed
  EventKit saves and removals report `STORE_FAILURE`. The setup commands report `CONFIG_INVALID`,
  `CONFIG_CONFLICT` and `SETUP_FAILED`. Reminders commands on a platform without Apple Reminders
  report `UNSUPPORTED_PLATFORM`.
- **Permissions.** `doctor` never shows the permission prompt. It reports each access state separately (not
  requested yet, denied, restricted, write-only, granted) and names what holds the permission (an app, or
  `reminders` itself when it is its own responsible process, as under Claude Desktop); only "not requested yet"
  points to `authorize`. Write-only access is not enough. A `Permissions app` check shows what macOS asks about
  (`reminders (this tool)` in that case). The original always named the launching app.
- **`doctor` and `authorize` exit 1 on failure, with or without `--json`.** `doctor` fails when any check fails;
  `authorize` fails unless Reminders access ends up fully granted (Full Disk Access is only needed for sections
  and doesn't count). With `--json` both still print their result on stdout, as
  `{"success": false, "data": ..., "error": ...}` when they fail: `CHECKS_FAILED` for `doctor`,
  `PERMISSION_DENIED` for `authorize`. `authorize --json` prints the outcome (`remindersAccess`,
  `databaseAccess`, `host`) instead of nothing.
- **Overdue** has one meaning everywhere: incomplete and due on a day before today. `lists` counts, listing
  headings and `overdue` agree. The original also counted reminders due today in `lists`, and completed reminders
  in headings.
- **Order.** Every reminder listing is sorted by due date (earliest first, undated last), in text and `--json`
  alike; the original's JSON kept Reminders' own order.
- **MCP results** are the CLI's `--json` data, wrapped in an object where it is a list (`{"lists": …}`,
  `{"reminders": …}`), because MCP structured content must be an object. Confirmations are the CLI's messages,
  such as `Completed "Buy milk" in "Groceries"`. Failures are `isError` results carrying the error code rather
  than bare text. Unknown arguments are rejected. As before, MCP deletions need no `confirm` argument: clients
  ask the user to approve destructive tools.
- **MCP reminder lookups.** `reminders_complete`, `reminders_update` and `reminders_delete` find the reminder
  by `title` or by `id` (an ID prefix, like the CLI's `--id`), and `id` wins when both are given. The schema
  marks neither as required because some clients reject a top-level `anyOf`; a call with neither is
  `INVALID_ARGUMENT`.
- **MCP calls run one at a time, in arrival order**, so a client that pipelines `create_list` and then `add`
  gets the list it just made.
- **Search** uses Foundation's `localizedStandardContains`, so it ignores diacritics as well as case (`cafe`
  finds `Café`).
- **Reminder lookups** use full EventKit identifiers internally, so changing a reminder never acts on a
  different reminder that shares an identifier prefix.
- **Text matching** follows Swift string semantics: canonically equivalent names match (`é` typed either way),
  and table columns are measured in terminal cells, so wide characters line up.
- **Corrupt section data** is reported as an error and never overwritten.
- **`demo`** is hidden from help and completions until it is implemented.

## Attribution

This project is a Swift rewrite of [remi](https://github.com/mattheworiordan/remi) by Matthew O'Riordan, released
under the MIT License; its copyright notice is kept in [LICENSE](LICENSE). The command set, the behaviour, and the
knowledge of how Apple Reminders stores and syncs sections come from that project.
