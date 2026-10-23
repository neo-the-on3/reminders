import ArgumentParser
import RemindersCore

/// Not implemented yet, so hidden from `--help` and from shell completions alike.
struct Demo: ConsoleCommand {
  static let configuration = CommandConfiguration(
    abstract: "Create a demo list to showcase reminders features", shouldDisplay: false)
  @OptionGroup var globals: GlobalOptions
  @Flag(help: "Remove the demo list") var cleanup = false

  func run(on console: Console) async throws {
    throw RemindersError.notImplemented("demo")
  }
}

struct Authorize: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Request Reminders access permission")
  @OptionGroup var globals: GlobalOptions

  func run(on console: Console) async throws {
    throw RemindersError.notImplemented("authorize")
  }
}

struct Doctor: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Check system health and diagnostics")
  @OptionGroup var globals: GlobalOptions
  @Flag(help: "Verify sync status") var sync = false
  @Flag(name: .customLong("db"), help: "Show database location and stats") var databaseStats = false

  func run(on console: Console) async throws {
    throw RemindersError.notImplemented("doctor")
  }
}

struct Completions: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Generate shell completions (bash, zsh, fish)")
  @OptionGroup var globals: GlobalOptions
  @Argument(help: "Shell type") var shell: CompletionShellKind

  func run(on console: Console) async throws {
    console.output.write(CompletionScript.generate(for: shell))
  }
}
