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
  @Flag(
    name: .customLong(String(PermissionGuidance.forMCPOption.dropFirst(2))),
    help: "Also open System Settings to turn on this tool's own entry, for MCP clients such as Claude Desktop")
  var forMCPServer = false

  /// Exits 1 unless the process ends up with full Reminders access.
  func run(in context: CommandContext) async throws {
    let diagnostics = Diagnostics(service: context.service, system: context.system)
    let report = await diagnostics.authorize(narratingTo: context.console, forMCPServer: forMCPServer)
    let failure = diagnostics.failure(of: report)
    context.console.show(report, failure: failure)
    if failure != nil { throw ExitCode.failure }
  }
}

struct Doctor: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Check system health and diagnostics")
  @OptionGroup var globals: GlobalOptions
  @Flag(help: "Verify sync status") var sync = false
  @Flag(name: .customLong("db"), help: "Show database location and stats") var databaseStats = false

  /// Exits 1 when a check fails, in text and JSON mode alike.
  func run(in context: CommandContext) async throws {
    let diagnostics = Diagnostics(service: context.service, system: context.system)
    let report = await diagnostics.checkHealth(includeDatabaseStats: databaseStats, includeSync: sync)
    context.console.show(report, failure: report.failure)
    if !report.passed { throw ExitCode.failure }
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
