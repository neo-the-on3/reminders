// Ported from the `completions` command in remi src/cli/index.ts (MIT, Matthew O'Riordan).

/// Supported shells for `remi completions`.
public enum CompletionShell: String, CaseIterable, Sendable {
  case bash, zsh, fish
}

/// A command name and its one-line description, as listed in completions.
public struct CommandSummary: Equatable, Sendable {
  public var name: String
  public var description: String

  public init(_ name: String, _ description: String) {
    self.name = name
    self.description = description
  }
}

/// Generate the completion script remi prints for `shell` (without the trailing newline).
public func completionScript(for shell: CompletionShell, commands: [CommandSummary]) -> String {
  let commands = commands.filter { $0.name != "completions" }
  switch shell {
  case .zsh:
    let entries = commands.map { "    '\($0.name):\($0.description)'" }.joined(separator: "\n")
    return """
      #compdef remi
      _remi() {
        local -a commands
        commands=(
      \(entries)
        )
        _describe 'command' commands
      }
      compdef _remi remi
      """
  case .bash:
    let names = commands.map(\.name).joined(separator: " ")
    return """
      _remi() {
        local commands="\(names)"
        COMPREPLY=($(compgen -W "$commands" -- "${COMP_WORDS[COMP_CWORD]}"))
      }
      complete -F _remi remi
      """
  case .fish:
    return commands.map { "complete -c remi -n '__fish_use_subcommand' -a '\($0.name)' -d '\($0.description)'" }
      .joined(separator: "\n")
  }
}
