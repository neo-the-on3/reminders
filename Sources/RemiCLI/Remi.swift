// Command-line entry point for the Swift port of remi (MIT, Matthew O'Riordan).
//
// The command surface mirrors remi's commander definition in src/cli/index.ts: same commands,
// aliases, arguments and options. Commands backed by Apple frameworks are wired up in later PRs and
// currently report a structured "not implemented" error.

import ArgumentParser
import Foundation
import RemiApple
import RemiCore

@main
struct Remi: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "remi",
    abstract: "Fast, reliable CLI for Apple Reminders with section support and iCloud sync",
    version: RemiVersion.current,
    subcommands: allCommands
  )

  /// Registration order matches remi (used for help and shell completions).
  static let allCommands: [any ParsableCommand.Type] = [
    Today.self, Upcoming.self, Overdue.self, ListCommand.self, Lists.self, Search.self, Add.self, Complete.self,
    Update.self, Delete.self, Sections.self, Move.self, CreateSection.self, DeleteSection.self, CreateList.self,
    DeleteList.self, Demo.self, Authorize.self, Doctor.self, Completions.self,
  ]

  @OptionGroup var globals: GlobalOptions

  static func main() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    // `remi --mcp` starts the MCP server instead of the CLI (as in remi)
    if arguments.contains("--mcp") {
      let output = Output.standard()
      output.error(
        RemiCommandError(.unknown, "MCP server mode is not implemented yet in the Swift port").toRemiError())
      Foundation.exit(1)
    }
    do {
      var command = try parseAsRoot(arguments)
      try command.run()
    } catch {
      exit(withError: error)
    }
  }
}

/// Options accepted by every command (`remi --json lists` and `remi lists --json` both work).
struct GlobalOptions: ParsableArguments {
  @Flag(name: .long, help: "Output in JSON format for machine consumption")
  var json = false

  @Flag(name: [.customShort("v"), .long], help: "Show additional details (notes preview, full dates)")
  var verbose = false
}

/// A remi subcommand: builds the shared ``Output`` and renders ``RemiCommandError``s like remi does.
protocol RemiCommand: ParsableCommand {
  var globals: GlobalOptions { get }
  func execute(_ output: Output) throws
}

extension RemiCommand {
  func run() throws {
    let output = Output.standard()
    output.jsonMode = globals.json
    output.verboseMode = globals.verbose
    do {
      try execute(output)
    } catch let error as RemiCommandError {
      output.error(error.toRemiError())
      throw ExitCode.failure
    } catch let error as ExitCode {
      throw error
    } catch {
      output.error(RemiError(code: .unknown, message: String(describing: error)))
      throw ExitCode.failure
    }
  }
}

/// Command names and descriptions in registration order, for `remi completions`.
var commandSummaries: [CommandSummary] {
  Remi.allCommands.map {
    CommandSummary($0.configuration.commandName!, $0.configuration.abstract)
  }
}
