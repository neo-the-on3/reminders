import ArgumentParser
import Foundation
import RemindersCore

/// Flags shared by the setup commands.
struct SetupFlags: ParsableArguments {
  @Flag(help: "Show what would change without changing anything")
  var dryRun = false

  @Flag(help: "Replace (or with --remove, delete) a reminders server that differs from this one")
  var force = false

  @Flag(help: "Remove the reminders server instead of adding it")
  var remove = false

  var options: SetupOptions { SetupOptions(dryRun: dryRun, force: force, remove: remove) }
}

extension ClaudeCodeScope: ExpressibleByArgument {}

/// An absolute path: `path` as given when absolute, else against the current directory.
private func absolute(_ path: String, in context: CommandContext) -> String {
  path.hasPrefix("/") ? path : URL(filePath: path, relativeTo: URL(filePath: context.setup.currentDirectory + "/")).path
}

struct SetupClaude: ConsoleCommand {
  static let configuration = CommandConfiguration(
    abstract: "Register the MCP server with Claude",
    discussion: """
      Adds a "reminders" server to Claude's config, \
      ~/Library/Application Support/Claude/claude_desktop_config.json, running this binary with --mcp. Other \
      servers and settings are kept, the file is backed up first, and running it again changes nothing.
      """)
  @OptionGroup var globals: GlobalOptions
  @OptionGroup var flags: SetupFlags
  @Option(help: ArgumentHelp("Edit this file instead of Claude's config", valueName: "file"))
  var config: String?

  func run(in context: CommandContext) async throws {
    let home = context.setup.homeDirectory
    let path = config.map { absolute($0, in: context) } ?? MCPSetup.claudeDesktopConfig(home: home)
    context.console.show(try MCPSetup(environment: context.setup).configure(.claudeDesktop, at: path, flags.options))
  }
}

struct SetupClaudeCode: ConsoleCommand {
  static let configuration = CommandConfiguration(
    abstract: "Register the MCP server with Claude Code",
    discussion: """
      Runs `claude mcp add --transport stdio --scope <scope> reminders -- <this binary> --mcp`, or prints that \
      command when `claude` isn't on PATH. An identical registration is left alone. local and project scopes \
      apply to the current directory.
      """)
  @OptionGroup var globals: GlobalOptions
  @OptionGroup var flags: SetupFlags
  @Option(help: "Where Claude Code keeps it: user (all projects), local (this project, just you), project (.mcp.json)")
  var scope: ClaudeCodeScope = .user

  func run(in context: CommandContext) async throws {
    let setup = MCPSetup(environment: context.setup)
    context.console.show(try await setup.configureClaudeCode(scope: scope, flags.options))
  }
}

struct SetupCursor: ConsoleCommand {
  static let configuration = CommandConfiguration(
    abstract: "Register the MCP server with Cursor",
    discussion: """
      Adds a "reminders" server to Cursor's global ~/.cursor/mcp.json, or with --project to <dir>/.cursor/mcp.json. \
      Other servers and settings are kept, the file is backed up first, and running it again changes nothing.
      """)
  @OptionGroup var globals: GlobalOptions
  @OptionGroup var flags: SetupFlags
  @Option(help: ArgumentHelp("Set up this project instead of every project", valueName: "dir"))
  var project: String?
  @Option(help: ArgumentHelp("Edit this file instead of Cursor's config", valueName: "file"))
  var config: String?

  func validate() throws {
    if project != nil && config != nil { throw ValidationError("Pass --project or --config, not both") }
  }

  func run(in context: CommandContext) async throws {
    if let config {
      let path = absolute(config, in: context)
      context.console.show(try MCPSetup(environment: context.setup).configure(.cursor, at: path, flags.options))
      return
    }
    var directory: String?
    if let project {
      let path = absolute(project, in: context)
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw RemindersError(
          .invalidArgument, "\(path) isn't a directory", suggestion: "Pass the project's root folder to --project")
      }
      directory = path
    }
    let path = MCPSetup.cursorConfig(home: context.setup.homeDirectory, project: directory)
    context.console.show(try MCPSetup(environment: context.setup).configure(.cursor, at: path, flags.options))
  }
}
