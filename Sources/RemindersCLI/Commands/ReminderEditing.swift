import ArgumentParser
import RemindersCore

/// The `<list> <title>` pair that names one reminder.
struct ReminderArguments: ParsableArguments {
  @Argument(help: "List name (fuzzy matched)") var list: String
  @Argument(help: "Reminder title (fuzzy matched)") var title: String

  func reference(id: String? = nil) -> ReminderReference {
    ReminderReference(list: list, title: title, id: id)
  }
}

struct Add: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Add a reminder to a list")
  @OptionGroup var globals: GlobalOptions
  @Argument(help: "List name (fuzzy matched)") var list: String
  @Argument(help: "Reminder title") var title: String
  @Option(help: "Add to a specific section") var section: String?
  @Option(help: "Due date: YYYY-MM-DD or natural language (\"tomorrow\", \"next friday\")") var due: String?
  @Option(help: "Priority") var priority: Priority = .none
  @Option(help: "Reminder notes") var notes: String?
  @Option(help: "Recurrence: \"daily\", \"weekly\", \"every 2 weeks\", \"every 3 months\"") var `repeat`: String?

  func run(in context: CommandContext) async throws {
    if section != nil { throw RemindersError.notImplemented("Adding to a section (--section)") }
    let request = NewReminderRequest(
      list: list, title: title, due: due, priority: priority, notes: notes, repeatRule: `repeat`)
    context.console.show(try await context.service.add(request))
  }
}

struct Complete: ConsoleCommand {
  static let configuration = CommandConfiguration(
    commandName: "complete", abstract: "Mark a reminder as complete", aliases: ["done"])
  @OptionGroup var globals: GlobalOptions
  @OptionGroup var reminder: ReminderArguments
  @Option(help: "Match by reminder ID prefix instead of title") var id: String?

  func run(in context: CommandContext) async throws {
    context.console.show(try await context.service.complete(reminder.reference(id: id)))
  }
}

struct Update: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Update a reminder")
  @OptionGroup var globals: GlobalOptions
  @OptionGroup var reminder: ReminderArguments
  @Option(name: .customLong("title"), help: "New title") var newTitle: String?
  @Option(help: "New due date: YYYY-MM-DD or natural language") var due: String?
  @Flag(help: "Remove due date") var clearDue = false
  @Option(help: "New priority") var priority: Priority?
  @Option(help: "New notes") var notes: String?

  func run(in context: CommandContext) async throws {
    let edit = ReminderEdit(title: newTitle, due: due, clearDue: clearDue, priority: priority, notes: notes)
    context.console.show(try await context.service.update(reminder.reference(), edit))
  }
}

struct Delete: ConsoleCommand {
  static let configuration = CommandConfiguration(
    commandName: "delete", abstract: "Delete a reminder", aliases: ["rm"])
  @OptionGroup var globals: GlobalOptions
  @OptionGroup var reminder: ReminderArguments
  @Option(help: "Match by reminder ID prefix instead of title") var id: String?
  @Flag(help: "Confirm deletion (required unless --json)") var confirm = false

  func run(in context: CommandContext) async throws {
    guard confirm || context.console.isJSON else {
      throw RemindersError(
        .invalidArgument, "Deletion requires --confirm flag",
        suggestion: "Run: \(ProductInfo.name) delete \"\(reminder.list)\" \"\(reminder.title)\" --confirm")
    }
    context.console.show(try await context.service.delete(reminder.reference(id: id)))
  }
}

extension Priority: ExpressibleByArgument {}
