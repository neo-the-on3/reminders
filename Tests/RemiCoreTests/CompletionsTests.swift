import Testing

@testable import RemiCore

@Suite("completions & styling")
struct CompletionsTests {
  let commands = [
    CommandSummary("today", "Show reminders due today"), CommandSummary("completions", "x"),
    CommandSummary("ls-like", "List it"),
  ]

  @Test("bash lists command names, excluding completions")
  func bash() {
    #expect(completionScript(for: .bash, commands: commands).contains(#"local commands="today ls-like""#))
  }

  @Test("zsh and fish include descriptions")
  func zshFish() {
    #expect(completionScript(for: .zsh, commands: commands).contains("    'today:Show reminders due today'"))
    #expect(
      completionScript(for: .fish, commands: commands)
        == "complete -c remi -n '__fish_use_subcommand' -a 'today' -d 'Show reminders due today'\ncomplete -c remi -n '__fish_use_subcommand' -a 'ls-like' -d 'List it'"
    )
  }

  @Test("styler emits chalk's sequences, re-opening around newlines and nested closes")
  func styler() {
    let style = Styler(level: .basic)
    #expect(style("x", .red) == "\u{1B}[31mx\u{1B}[39m")
    #expect(style("x", .bold, .underline) == "\u{1B}[1m\u{1B}[4mx\u{1B}[24m\u{1B}[22m")
    #expect(style("a\nb", .bold) == "\u{1B}[1ma\u{1B}[22m\n\u{1B}[1mb\u{1B}[22m")
    #expect(style(style("x", .dim), .bold) == "\u{1B}[1m\u{1B}[2mx\u{1B}[22m\u{1B}[1m\u{1B}[22m")
    #expect(Styler.plain("x", .red) == "x")
  }
}
