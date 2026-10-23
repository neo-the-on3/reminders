import ArgumentParser
import RemindersCore

struct Sections: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "List sections in a reminder list")
  @OptionGroup var globals: GlobalOptions
  @Argument(help: "List name (fuzzy matched)") var list: String

  func run(in context: CommandContext) async throws {
    context.console.show(try await context.service.sections(ofList: list))
  }
}

struct Move: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Move a reminder to a different section")
  @OptionGroup var globals: GlobalOptions
  @OptionGroup var reminder: ReminderArguments
  @Option(help: "Target section name") var toSection: String

  func run(in context: CommandContext) async throws {
    throw RemindersError.notImplemented("move")
  }
}

struct CreateSection: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Create a section in a reminder list")
  @OptionGroup var globals: GlobalOptions
  @Argument(help: "List name (fuzzy matched)") var list: String
  @Argument(help: "Name of the new section") var name: String

  func run(in context: CommandContext) async throws {
    context.console.show(try await context.service.createSection(named: name, inList: list))
  }
}

struct DeleteSection: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Delete a section from a reminder list")
  @OptionGroup var globals: GlobalOptions
  @Argument(help: "List name (fuzzy matched)") var list: String
  @Argument(help: "Section name (fuzzy matched)") var name: String
  @Flag(help: "Confirm deletion (required unless --json)") var confirm = false

  func run(in context: CommandContext) async throws {
    guard confirm || context.console.isJSON else {
      throw RemindersError(
        .invalidArgument, "Section deletion requires --confirm flag",
        suggestion: "Run: \(ProductInfo.name) delete-section \"\(list)\" \"\(name)\" --confirm")
    }
    context.console.show(try await context.service.deleteSection(named: name, inList: list))
  }
}
