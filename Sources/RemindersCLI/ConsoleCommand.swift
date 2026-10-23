import ArgumentParser
import RemindersApple
import RemindersCore

/// Flags every command accepts, before or after the command name (`reminders --json lists`, `reminders lists --json`).
struct GlobalOptions: ParsableArguments {
  @Flag(help: "Output in JSON format for machine consumption")
  var json = false

  @Flag(
    name: [.customShort("v"), .long],
    help: "Preview each reminder's notes when listing reminders as text (other output is unchanged)")
  var verbose = false
}

/// What a command works with: where output goes, the reminder operations and the machine facts.
struct CommandContext: Sendable {
  var console: Console
  var service: RemindersService
  var system: any SystemProbe
  /// Home, binary and `PATH` for the setup commands.
  var setup: SetupEnvironment = .live()

  /// The real thing: stdout/stderr, the platform's Reminders store and this machine.
  static func live(_ globals: GlobalOptions) -> CommandContext {
    let system = RemindersPlatform.makeSystemProbe()
    return CommandContext(
      console: .standard(format: globals.json ? .json : .text, verbose: globals.verbose),
      service: RemindersPlatform.makeService(system: system),
      system: system)
  }
}

/// A subcommand that reports through a ``Console``: results in the requested format, and any ``RemindersError``
/// as a structured failure with exit status 1.
protocol ConsoleCommand: AsyncParsableCommand {
  var globals: GlobalOptions { get }
  func run(in context: CommandContext) async throws
}

extension ConsoleCommand {
  func run() async throws {
    try await execute(in: .live(globals))
  }

  /// Runs the command, reporting failures on the context's console.
  func execute(in context: CommandContext) async throws {
    do {
      try await run(in: context)
    } catch let exit as ExitCode {
      throw exit
    } catch {
      context.console.report(RemindersError(wrapping: error))
      throw ExitCode.failure
    }
  }
}
