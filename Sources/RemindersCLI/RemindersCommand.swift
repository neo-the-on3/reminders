import ArgumentParser
import Foundation
import MCP
import RemindersApple
import RemindersCore
import RemindersMCP

@main
struct RemindersCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: ProductInfo.name,
    abstract: "Fast, reliable CLI for Apple Reminders with section support and iCloud sync",
    version: ProductInfo.version,
    subcommands: [
      Today.self, Upcoming.self, Overdue.self, ListContents.self, Lists.self, Search.self,
      Add.self, Complete.self, Update.self, Delete.self,
      Sections.self, Move.self, CreateSection.self, DeleteSection.self,
      CreateList.self, DeleteList.self,
      Demo.self, Authorize.self, Doctor.self, Completions.self,
    ]
  )

  @OptionGroup var globals: GlobalOptions

  static func main() async {
    let arguments = Array(CommandLine.arguments.dropFirst())
    // `reminders --mcp` serves the commands as MCP tools on stdin/stdout instead of running the CLI.
    if arguments.contains("--mcp") {
      do {
        // macOS attributes Reminders access to the client app that started the server, so errors name it.
        let permissions = PermissionGuidance(host: RemindersPlatform.makeSystemProbe().hostApplication)
        let server = RemindersMCPServer(
          service: RemindersService(store: RemindersPlatform.makeStore(), permissions: permissions))
        try await server.run(on: DrainingTransport(StdioTransport()))
      } catch {
        StandardStream(.error).write("reminders --mcp: \(error)\n")
        Foundation.exit(ExitCode.failure.rawValue)
      }
      return
    }
    do {
      var command = try parseAsRoot(arguments)
      if var command = command as? any AsyncParsableCommand {
        try await command.run()
      } else {
        try command.run()
      }
    } catch {
      exit(withError: error)
    }
  }
}
