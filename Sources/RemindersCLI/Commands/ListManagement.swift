import ArgumentParser
import RemindersCore

struct CreateList: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Create a new reminder list")
  @OptionGroup var globals: GlobalOptions
  @Argument(help: "Name of the new list") var name: String

  func run(on console: Console) async throws {
    throw RemindersError.notImplemented("create-list")
  }
}

struct DeleteList: ConsoleCommand {
  static let configuration = CommandConfiguration(abstract: "Delete a reminder list")
  @OptionGroup var globals: GlobalOptions
  @Argument(help: "List name (fuzzy matched)") var name: String
  @Flag(help: "Confirm deletion (required unless --json)") var confirm = false

  func run(on console: Console) async throws {
    throw RemindersError.notImplemented("delete-list")
  }
}
