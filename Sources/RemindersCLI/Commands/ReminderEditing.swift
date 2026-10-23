import ArgumentParser
import RemindersCore

/// The `<list> <title>` pair that names one reminder.
struct ReminderReference: ParsableArguments {
  @Argument(help: "List name (fuzzy matched)") var list: String
  @Argument(help: "Reminder title (fuzzy matched)") var title: String
}

struct Add: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Add a reminder to a list")
  @OptionGroup var globals: GlobalOptions
  @Argument(help: "List name (fuzzy matched)") var list: String
  @Argument(help: "Reminder title") var title: String
  @Option(help: "Add to a specific section") var section: String?
  @Option(help: "Due date: YYYY-MM-DD or natural language (\"tomorrow\", \"next friday\")") var due: String?
  @Option(help: "Priority: none, low, medium, high") var priority: Priority = .none
  @Option(help: "Reminder notes") var notes: String?
  @Option(help: "Recurrence: \"daily\", \"weekly\", \"every 2 weeks\", \"every 3 months\"") var `repeat`: String?

  func run(on console: Console) async throws {
    throw RemindersError.notImplemented("add")
  }
}

struct Complete: ConsoleCommand {
  static let configuration = CommandConfiguration(
    commandName: "complete", abstract: "Mark a reminder as complete", aliases: ["done"])
  @OptionGroup var globals: GlobalOptions
  @OptionGroup var reminder: ReminderReference
  @Option(help: "Match by reminder ID prefix instead of title") var id: String?

  func run(on console: Console) async throws {
    throw RemindersError.notImplemented("complete")
  }
}

struct Update: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Update a reminder")
  @OptionGroup var globals: GlobalOptions
  @OptionGroup var reminder: ReminderReference
  @Option(name: .customLong("title"), help: "New title") var newTitle: String?
  @Option(help: "New due date: YYYY-MM-DD or natural language") var due: String?
  @Flag(help: "Remove due date") var clearDue = false
  @Option(help: "New priority: none, low, medium, high") var priority: Priority?
  @Option(help: "New notes") var notes: String?

  func run(on console: Console) async throws {
    throw RemindersError.notImplemented("update")
  }
}

struct Delete: ConsoleCommand {
  static let configuration = CommandConfiguration(
    commandName: "delete", abstract: "Delete a reminder", aliases: ["rm"])
  @OptionGroup var globals: GlobalOptions
  @OptionGroup var reminder: ReminderReference
  @Option(help: "Match by reminder ID prefix instead of title") var id: String?
  @Flag(help: "Confirm deletion (required unless --json)") var confirm = false

  func run(on console: Console) async throws {
    throw RemindersError.notImplemented("delete")
  }
}

extension Priority: ExpressibleByArgument {}
