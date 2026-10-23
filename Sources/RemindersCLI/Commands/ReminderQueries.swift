import ArgumentParser
import RemindersCore

struct Today: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Show reminders due today")
  @OptionGroup var globals: GlobalOptions

  func run(in context: CommandContext) async throws {
    context.console.show(try await context.service.dueToday())
  }
}

struct Upcoming: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Show upcoming reminders")
  @OptionGroup var globals: GlobalOptions
  @Option(help: "Number of days to look ahead") var days = 7

  func run(in context: CommandContext) async throws {
    context.console.show(try await context.service.upcoming(days: days))
  }
}

struct Overdue: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Show overdue reminders")
  @OptionGroup var globals: GlobalOptions

  func run(in context: CommandContext) async throws {
    context.console.show(try await context.service.overdue())
  }
}

struct ListContents: ConsoleCommand {
  static let configuration = CommandConfiguration(commandName: "list", abstract: "Show contents of a reminder list")
  @OptionGroup var globals: GlobalOptions
  @Argument(help: "List name (fuzzy matched)") var name: String
  @Option(help: "Filter by section") var section: String?
  @Flag(help: "Include completed reminders") var includeCompleted = false

  func run(in context: CommandContext) async throws {
    if section != nil { throw RemindersError.notImplemented("Filtering by section (--section)") }
    context.console.show(try await context.service.contents(ofList: name, includeCompleted: includeCompleted))
  }
}

struct Lists: ConsoleCommand {
  static let configuration = CommandConfiguration(
    commandName: "lists", abstract: "List all reminder lists", aliases: ["ls"])
  @OptionGroup var globals: GlobalOptions

  func run(in context: CommandContext) async throws {
    context.console.show(try await context.service.listOverview())
  }
}

struct Search: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Search reminders across all lists")
  @OptionGroup var globals: GlobalOptions
  @Argument(help: "Text to find in titles and notes") var query: String

  func run(in context: CommandContext) async throws {
    context.console.show(try await context.service.search(query))
  }
}
