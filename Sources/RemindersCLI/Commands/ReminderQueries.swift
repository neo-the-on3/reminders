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
  static let configuration = CommandConfiguration(
    abstract: "Show reminders due from today through the next N days",
    discussion: "Overdue reminders aren't included; see 'overdue'.")
  @OptionGroup var globals: GlobalOptions
  // `.unconditional` takes the next word even when it starts with "-", so `--days -1` reaches the service's check
  // (INVALID_ARGUMENT) instead of failing as a missing value.
  @Option(parsing: .unconditional, help: "Days to look ahead after today (0 = today only)") var days = 7

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
  @Option(help: "Only reminders in this section (fuzzy matched)") var section: String?
  @Flag(help: "Only reminders in no section (shown under \"Others\")") var unsectioned = false
  @Flag(help: "Include completed reminders") var includeCompleted = false

  func run(in context: CommandContext) async throws {
    let listing = try await context.service.contents(
      ofList: name, section: section, unsectioned: unsectioned, includeCompleted: includeCompleted)
    context.console.show(listing)
    if let problem = listing.sectionsUnavailable {
      context.console.hint(
        "Sections couldn't be read, so they aren't shown: \(problem.message). "
          + "Run `\(ProductInfo.name) doctor` to check ReminderKit.\n")
    }
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
