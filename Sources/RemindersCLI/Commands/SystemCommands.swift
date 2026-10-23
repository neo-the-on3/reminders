import ArgumentParser
import RemindersCore

/// Not implemented yet, so hidden from `--help` and from shell completions alike.
struct Demo: ConsoleCommand {
  static let configuration = CommandConfiguration(
    abstract: "Create a demo list to showcase reminders features", shouldDisplay: false)
  @OptionGroup var globals: GlobalOptions
  @Flag(help: "Remove the demo list") var cleanup = false

  func run(in context: CommandContext) async throws {
    throw RemindersError.notImplemented("demo")
  }
}

struct Authorize: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Request Reminders access permission")
  @OptionGroup var globals: GlobalOptions

  func run(in context: CommandContext) async throws {
    let diagnostics = Diagnostics(service: context.service, system: context.system)
    context.console.show(await diagnostics.authorize(narratingTo: context.console))
  }
}

struct Doctor: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Check system health and diagnostics")
  @OptionGroup var globals: GlobalOptions
  @Flag(help: "Verify sync status") var sync = false
  @Flag(name: .customLong("db"), help: "Show database location and stats") var databaseStats = false

  /// Exits 1 when a check fails. With `--json` the checks are the result and the exit status is 0.
  func run(in context: CommandContext) async throws {
    let diagnostics = Diagnostics(service: context.service, system: context.system)
    let report = await diagnostics.checkHealth(includeDatabaseStats: databaseStats, includeSync: sync)
    context.console.show(report)
    if !report.passed && !context.console.isJSON { throw ExitCode.failure }
  }
}

struct Completions: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Generate shell completions (bash, zsh, fish)")
  @OptionGroup var globals: GlobalOptions
  @Argument(help: "Shell type") var shell: CompletionShellKind

  func run(in context: CommandContext) async throws {
    context.console.output.write(CompletionScript.generate(for: shell))
  }
}
