import ArgumentParser
import RemindersCore

struct CreateList: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Create a new reminder list")
  @OptionGroup var globals: GlobalOptions
  @Argument(help: "Name of the new list") var name: String

  func run(in context: CommandContext) async throws {
    context.console.show(try await context.service.createList(named: name))
  }
}

struct DeleteList: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Delete a reminder list")
  @OptionGroup var globals: GlobalOptions
  @Argument(help: "List name (fuzzy matched)") var name: String
  @Flag(help: "Confirm deletion (required unless --json)") var confirm = false

  func run(in context: CommandContext) async throws {
    guard confirm || context.console.isJSON else {
      throw RemindersError(
        .invalidArgument, "List deletion requires --confirm flag",
        suggestion: "Run: \(ProductInfo.name) delete-list \"\(name)\" --confirm")
    }
    context.console.show(try await context.service.deleteList(named: name))
  }
}
