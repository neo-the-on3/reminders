import ArgumentParser
import RemindersCore

/// Flags every command accepts, before or after the command name (`reminders --json lists`, `reminders lists --json`).
struct GlobalOptions: ParsableArguments {
  @Flag(help: "Output in JSON format for machine consumption")
  var json = false

  @Flag(name: [.customShort("v"), .long], help: "Show additional details (notes preview, full dates)")
  var verbose = false
}

/// A subcommand that reports through a ``Console``: results in the requested format, and any ``RemindersError``
/// as a structured failure with exit status 1.
protocol ConsoleCommand: AsyncParsableCommand {
  var globals: GlobalOptions { get }
  func run(on console: Console) async throws
}

extension ConsoleCommand {
  func run() async throws {
    let console = Console.standard(format: globals.json ? .json : .text, verbose: globals.verbose)
    do {
      try await run(on: console)
    } catch let exit as ExitCode {
      throw exit
    } catch {
      console.report(RemindersError(wrapping: error))
      throw ExitCode.failure
    }
  }
}
