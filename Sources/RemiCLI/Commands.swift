// remi's commands. The section commands are placeholders until the ReminderKit/SQLite layers land.

import ArgumentParser
import RemiApple
import RemiCore

// MARK: - Daily drivers: queries

struct Today: RemiCommand {
  static let configuration = CommandConfiguration(
    commandName: "today", abstract: "Show reminders due today")
  @OptionGroup var globals: GlobalOptions
  func execute(_ output: Output) async throws {
    try await reminders(output).today()
  }
}

struct Upcoming: RemiCommand {
  static let configuration = CommandConfiguration(
    commandName: "upcoming", abstract: "Show upcoming reminders")
  @OptionGroup var globals: GlobalOptions
  @Option(help: "Number of days to look ahead") var days = "7"
  func execute(_ output: Output) async throws {
    try await reminders(output).upcoming(days: days)
  }
}

struct Overdue: RemiCommand {
  static let configuration = CommandConfiguration(
    commandName: "overdue", abstract: "Show overdue reminders")
  @OptionGroup var globals: GlobalOptions
  func execute(_ output: Output) async throws {
    try await reminders(output).overdue()
  }
}

// MARK: - Browse

struct ListCommand: RemiCommand {
  static let configuration = CommandConfiguration(commandName: "list", abstract: "Show contents of a reminder list")
  @OptionGroup var globals: GlobalOptions
  @Argument var name: String
  @Option(help: "Filter by section") var section: String?
  @Flag(help: "Include completed reminders") var includeCompleted = false
  func execute(_ output: Output) async throws {
    try await reminders(output).list(name, includeCompleted: includeCompleted)
  }
}

struct Lists: RemiCommand {
  static let configuration = CommandConfiguration(
    commandName: "lists", abstract: "List all reminder lists", aliases: ["ls"])
  @OptionGroup var globals: GlobalOptions
  func execute(_ output: Output) async throws {
    try await reminders(output).lists()
  }
}

struct Search: RemiCommand {
  static let configuration = CommandConfiguration(
    commandName: "search", abstract: "Search reminders across all lists")
  @OptionGroup var globals: GlobalOptions
  @Argument var query: String
  func execute(_ output: Output) async throws {
    try await reminders(output).search(query)
  }
}

// MARK: - Task actions

struct Add: RemiCommand {
  static let configuration = CommandConfiguration(
    commandName: "add", abstract: "Add a reminder to a list")
  @OptionGroup var globals: GlobalOptions
  @Argument var list: String
  @Argument var title: String
  @Option(help: "Add to a specific section") var section: String?
  @Option(help: "Due date: YYYY-MM-DD or natural language (\"tomorrow\", \"next friday\")") var due: String?
  @Option(help: "Priority: none, low, medium, high") var priority = "none"
  @Option(help: "Reminder notes") var notes: String?
  @Option(help: "Recurrence: \"daily\", \"weekly\", \"every 2 weeks\", \"every 3 months\"") var `repeat`: String?
  func execute(_ output: Output) async throws {
    try await reminders(output).add(
      list: list, title: title, section: section, due: due, priority: priority, notes: notes, repeat: `repeat`)
  }
}

struct Complete: RemiCommand {
  static let configuration = CommandConfiguration(
    commandName: "complete", abstract: "Mark a reminder as complete", aliases: ["done"])
  @OptionGroup var globals: GlobalOptions
  @Argument var list: String
  @Argument var title: String
  @Option(help: "Match by reminder ID instead of title") var id: String?
  func execute(_ output: Output) async throws {
    try await reminders(output).complete(list: list, title: title, id: id)
  }
}

struct Update: RemiCommand {
  static let configuration = CommandConfiguration(
    commandName: "update", abstract: "Update a reminder")
  @OptionGroup var globals: GlobalOptions
  @Argument var list: String
  @Argument var title: String
  @Option(name: .customLong("title"), help: "New title") var newTitle: String?
  @Option(help: "New due date: YYYY-MM-DD or natural language") var due: String?
  @Flag(help: "Remove due date") var clearDue = false
  @Option(help: "New priority: none, low, medium, high") var priority: String?
  @Option(help: "New notes") var notes: String?
  func execute(_ output: Output) async throws {
    try await reminders(output).update(
      list: list, title: title, newTitle: newTitle, due: due, clearDue: clearDue, priority: priority, notes: notes)
  }
}

struct Delete: RemiCommand {
  static let configuration = CommandConfiguration(
    commandName: "delete", abstract: "Delete a reminder", aliases: ["rm"])
  @OptionGroup var globals: GlobalOptions
  @Argument var list: String
  @Argument var title: String
  @Option(help: "Match by reminder ID instead of title") var id: String?
  @Flag(help: "Confirm deletion (required in interactive mode)") var confirm = false
  func execute(_ output: Output) async throws {
    try await reminders(output).delete(list: list, title: title, id: id, confirm: confirm)
  }
}

// MARK: - Organization: sections and lists

struct Sections: RemiCommand {
  static let configuration = CommandConfiguration(
    commandName: "sections", abstract: "List sections in a reminder list")
  @OptionGroup var globals: GlobalOptions
  @Argument var list: String
  func execute(_ output: Output) async throws { throw ApplePlatform.unavailable("remi sections") }
}

struct Move: RemiCommand {
  static let configuration = CommandConfiguration(
    commandName: "move", abstract: "Move a reminder to a different section")
  @OptionGroup var globals: GlobalOptions
  @Argument var list: String
  @Argument var title: String
  @Option(help: "Target section name") var toSection: String
  func execute(_ output: Output) async throws { throw ApplePlatform.unavailable("remi move") }
}

struct CreateSection: RemiCommand {
  static let configuration = CommandConfiguration(
    commandName: "create-section", abstract: "Create a section in a reminder list")
  @OptionGroup var globals: GlobalOptions
  @Argument var list: String
  @Argument var name: String
  func execute(_ output: Output) async throws { throw ApplePlatform.unavailable("remi create-section") }
}

struct DeleteSection: RemiCommand {
  static let configuration = CommandConfiguration(
    commandName: "delete-section", abstract: "Delete a section from a reminder list")
  @OptionGroup var globals: GlobalOptions
  @Argument var list: String
  @Argument var name: String
  func execute(_ output: Output) async throws { throw ApplePlatform.unavailable("remi delete-section") }
}

struct CreateList: RemiCommand {
  static let configuration = CommandConfiguration(commandName: "create-list", abstract: "Create a new reminder list")
  @OptionGroup var globals: GlobalOptions
  @Argument var name: String
  func execute(_ output: Output) async throws {
    try await reminders(output).createList(name)
  }
}

struct DeleteList: RemiCommand {
  static let configuration = CommandConfiguration(commandName: "delete-list", abstract: "Delete a reminder list")
  @OptionGroup var globals: GlobalOptions
  @Argument var name: String
  @Flag(help: "Confirm deletion (required in interactive mode)") var confirm = false
  func execute(_ output: Output) async throws {
    try await reminders(output).deleteList(name, confirm: confirm)
  }
}

// MARK: - System

struct Demo: RemiCommand {
  static let configuration = CommandConfiguration(
    commandName: "demo", abstract: "Create a demo list to showcase remi features", shouldDisplay: false)
  @OptionGroup var globals: GlobalOptions
  @Flag(help: "Remove the demo list") var cleanup = false
  func execute(_ output: Output) async throws { throw ApplePlatform.unavailable("remi demo") }
}

struct Authorize: RemiCommand {
  static let configuration = CommandConfiguration(
    commandName: "authorize", abstract: "Request Reminders access permission")
  @OptionGroup var globals: GlobalOptions
  func execute(_ output: Output) async throws {
    await reminders(output).authorize(system: ApplePlatform.makeSystemEnvironment())
  }
}

struct Doctor: RemiCommand {
  static let configuration = CommandConfiguration(
    commandName: "doctor", abstract: "Check system health and diagnostics")
  @OptionGroup var globals: GlobalOptions
  @Flag(help: "Verify sync status") var sync = false
  @Flag(help: "Show database location and stats") var db = false
  func execute(_ output: Output) async throws {
    let passed = await reminders(output).doctor(system: ApplePlatform.makeSystemEnvironment(), databaseStats: db)
    if !passed { throw ExitCode.failure }
  }
}

struct Completions: RemiCommand {
  static let configuration = CommandConfiguration(
    commandName: "completions", abstract: "Generate shell completions (bash, zsh, fish)")
  @OptionGroup var globals: GlobalOptions
  @Argument(help: "Shell type: bash, zsh, or fish") var shell: String

  func execute(_ output: Output) async throws {
    guard let kind = RemiCore.CompletionShell(rawValue: shell) else {
      output.stderr.write("Unknown shell: \(shell). Use: bash, zsh, or fish\n")
      throw ExitCode.failure
    }
    output.stdout.write(RemiCore.completionScript(for: kind, commands: commandSummaries) + "\n")
  }
}
