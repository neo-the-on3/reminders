import ArgumentParser
import RemindersApple
import RemindersCore

/// For working out which ReminderKit getters hold section data on a new macOS version. Read-only; hidden from
/// `--help` and completions.
struct DebugReminderKit: ConsoleCommand {
  static let configuration = CommandConfiguration(
    commandName: "debug-reminderkit",
    abstract: "Show what ReminderKit exposes about a list's sections (read-only)", shouldDisplay: false)
  @OptionGroup var globals: GlobalOptions
  @Option(help: "List name (fuzzy matched)") var list: String
  @Flag(help: "List every method and property of the classes, not just those about sections and order")
  var allSelectors = false
  @Flag(help: "Also build a list change, never saved, to read the values it starts with")
  var changeItem = false
  @Option(help: "The most reminders to ask about") var limit = 200

  func run(in context: CommandContext) async throws {
    let target = try await context.service.lists().resolve(list)
    let output = context.console.output
    try ReminderKitProbe.run(
      on: target, options: .init(allSelectors: allSelectors, changeItem: changeItem, reminderLimit: limit)
    ) { output.write($0 + "\n") }
  }
}
