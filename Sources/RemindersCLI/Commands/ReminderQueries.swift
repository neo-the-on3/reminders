import ArgumentParser
import RemindersCore

struct Today: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Show reminders due today")
  @OptionGroup var globals: GlobalOptions

  func run(on console: Console) async throws {
    throw RemindersError.notImplemented("today")
  }
}

struct Upcoming: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Show upcoming reminders")
  @OptionGroup var globals: GlobalOptions
  @Option(help: "Number of days to look ahead") var days = 7

  func run(on console: Console) async throws {
    throw RemindersError.notImplemented("upcoming")
  }
}

struct Overdue: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Show overdue reminders")
  @OptionGroup var globals: GlobalOptions

  func run(on console: Console) async throws {
    throw RemindersError.notImplemented("overdue")
  }
}

struct ListContents: ConsoleCommand {
  static let configuration = CommandConfiguration(commandName: "list", abstract: "Show contents of a reminder list")
  @OptionGroup var globals: GlobalOptions
  @Argument(help: "List name (fuzzy matched)") var name: String
  @Option(help: "Filter by section") var section: String?
  @Flag(help: "Include completed reminders") var includeCompleted = false

  func run(on console: Console) async throws {
    throw RemindersError.notImplemented("list")
  }
}

struct Lists: ConsoleCommand {
  static let configuration = CommandConfiguration(
    commandName: "lists", abstract: "List all reminder lists", aliases: ["ls"])
  @OptionGroup var globals: GlobalOptions

  func run(on console: Console) async throws {
    throw RemindersError.notImplemented("lists")
  }
}

struct Search: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Search reminders across all lists")
  @OptionGroup var globals: GlobalOptions
  @Argument(help: "Text to find in titles and notes") var query: String

  func run(on console: Console) async throws {
    throw RemindersError.notImplemented("search")
  }
}
