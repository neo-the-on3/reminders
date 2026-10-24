import Testing

@testable import RemindersCore

private let path = "/Users/me/Library/Application Support/Claude/claude_desktop_config.json"
private let entry = MCPServerEntry(command: "/opt/homebrew/opt/reminders/bin/reminders")

/// A Claude config with another server and a top-level preference, indented with four spaces.
private let existing = """
  {
      "mcpServers": {
          "filesystem": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/me/Desktop"],
              "env": {"DEBUG": "1"}
          }
      },
      "globalShortcut": "Alt+Space"
  }

  """

private func code(_ body: () throws -> Void) -> RemindersError.Code? {
  do {
    try body()
    return nil
  } catch let error as RemindersError {
    return error.code
  } catch {
    return .unknown
  }
}

@Suite("MCP setup: editing a client's config")
struct MCPConfigDocumentTests {
  @Test("a missing or empty file becomes one with just the reminders server")
  func newFile() throws {
    for text in [nil, "", "  \n"] {
      let edit = try MCPConfigDocument(text, path: path).adding(entry, force: false)
      #expect(edit.outcome == .added)
      #expect(
        edit.text == """
          {
            "mcpServers": {
              "reminders": {
                "command": "/opt/homebrew/opt/reminders/bin/reminders",
                "args": ["--mcp"]
              }
            }
          }

          """)
    }
  }

  @Test("other servers, other keys, their order and their layout are kept byte for byte")
  func merge() throws {
    let edit = try MCPConfigDocument(existing, path: path).adding(entry, force: false)
    #expect(edit.outcome == .added)
    #expect(
      edit.text == """
        {
            "mcpServers": {
                "filesystem": {
                    "command": "npx",
                    "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/me/Desktop"],
                    "env": {"DEBUG": "1"}
                },
                "reminders": {
                    "command": "/opt/homebrew/opt/reminders/bin/reminders",
                    "args": ["--mcp"]
                }
            },
            "globalShortcut": "Alt+Space"
        }

        """)
  }

  @Test("a file without mcpServers gets it at the end; tabs stay tabs")
  func noServers() throws {
    let edit = try MCPConfigDocument("{\n\t\"theme\": \"dark\"\n}\n", path: path).adding(entry, force: false)
    #expect(edit.text?.hasPrefix("{\n\t\"theme\": \"dark\",\n\t\"mcpServers\": {\n\t\t\"reminders\": {") == true)
  }

  @Test("adding again is a no-op; a stdio type and empty env count as the same entry")
  func idempotent() throws {
    let added = try #require(try MCPConfigDocument(existing, path: path).adding(entry, force: false).text)
    #expect(try MCPConfigDocument(added, path: path).adding(entry, force: false).outcome == .unchanged)
    let cursor = MCPServerEntry(command: entry.command, type: "stdio")
    #expect(try MCPConfigDocument(added, path: path).adding(cursor, force: false).outcome == .unchanged)
    let claudeCode = """
      {"mcpServers":{"reminders":{"type":"stdio","command":"\(entry.command)","args":["--mcp"],"env":{}}}}
      """
    #expect(try MCPConfigDocument(claudeCode, path: path).adding(entry, force: false).outcome == .unchanged)
  }

  @Test("a different reminders entry needs --force to replace or remove")
  func conflict() throws {
    let other = #"{"mcpServers":{"reminders":{"command":"/usr/local/bin/reminders","args":["--mcp"]}}}"#
    let document = try MCPConfigDocument(other, path: path)
    #expect(code { _ = try document.adding(entry, force: false) } == .configConflict)
    #expect(code { _ = try document.removing(entry, force: false) } == .configConflict)
    do {
      _ = try document.adding(entry, force: false)
    } catch {
      #expect(error.message.contains(#""command":"/usr/local/bin/reminders""#))
      #expect(error.suggestion?.contains("--force") == true)
    }
    let replaced = try document.adding(entry, force: true)
    #expect(replaced.outcome == .replaced)
    #expect(replaced.text?.contains(entry.command) == true)
    #expect(replaced.text?.contains("/usr/local/bin") == false)
    let withEnv = #"{"mcpServers":{"reminders":{"command":"\#(entry.command)","args":["--mcp"],"env":{"A":"1"}}}}"#
    #expect(code { _ = try MCPConfigDocument(withEnv, path: path).adding(entry, force: false) } == .configConflict)
  }

  @Test("removing takes out only the reminders entry, and is a no-op when it isn't there")
  func remove() throws {
    let added = try #require(try MCPConfigDocument(existing, path: path).adding(entry, force: false).text)
    let removed = try MCPConfigDocument(added, path: path).removing(entry, force: false)
    #expect(removed.outcome == .removed)
    #expect(removed.text?.contains("reminders") == false)
    #expect(removed.text?.contains("filesystem") == true)
    #expect(removed.text?.contains("globalShortcut") == true)
    #expect(try MCPConfigDocument(existing, path: path).removing(entry, force: false).outcome == .absent)
    #expect(try MCPConfigDocument(nil, path: path).removing(entry, force: false).outcome == .absent)
  }

  @Test(
    "adding then removing gives the original text back",
    arguments: [
      existing,
      #"{"mcpServers":{"filesystem":{"command":"npx","args":["-y"]}},"theme":"dark"}"#,
      #"{ "mcpServers": { "a": { "command": "a" } } }"# + "\n",
      "{\r\n  \"mcpServers\": {\r\n    \"a\": {\"command\": \"a\"}\r\n  }\r\n}\r\n",
    ])
  func roundTrip(original: String) throws {
    let added = try #require(try MCPConfigDocument(original, path: path).adding(entry, force: false).text)
    #expect(try MCPConfigDocument(added, path: path).existingEntry != nil)
    #expect(try MCPConfigDocument(added, path: path).removing(entry, force: false).text == original)
  }

  @Test("a new entry follows its neighbours' layout: one-line objects stay on one line")
  func compact() throws {
    let oneLine = #"{"mcpServers": {"a": {"command": "a"}}}"#
    #expect(
      try MCPConfigDocument(oneLine, path: path).adding(entry, force: false).text
        == #"{"mcpServers": {"a": {"command": "a"},"reminders": {"command":"\#(entry.command)","args":["--mcp"]}}}"#)
    let crlf = "{\r\n  \"mcpServers\": {\r\n    \"a\": 1\r\n  }\r\n}\r\n"
    let added = try #require(try MCPConfigDocument(crlf, path: path).adding(entry, force: false).text)
    #expect(added.contains("\"a\": 1,\r\n    \"reminders\": {\r\n      \"command\""))
    #expect(!added.replacing("\r\n", with: "").contains("\n"))
  }

  @Test("removing or replacing an existing entry touches only its own text")
  func inPlace() throws {
    let first = """
      {
        "mcpServers": {
          "reminders": {"command": "/old/reminders", "args": ["--mcp"]},
          "b": {"command": "b"}
        }
      }
      """
    #expect(
      try MCPConfigDocument(first, path: path).removing(entry, force: true).text
        == "{\n  \"mcpServers\": {\n    \"b\": {\"command\": \"b\"}\n  }\n}")
    #expect(
      try MCPConfigDocument(first, path: path).adding(entry, force: true).text
        == first.replacing(
          #"{"command": "/old/reminders", "args": ["--mcp"]}"#,
          with: #"{"command":"\#(entry.command)","args":["--mcp"]}"#))
    let only = #"{"mcpServers": {"reminders": {"command": "/old/reminders"}}, "x": 1}"#
    #expect(try MCPConfigDocument(only, path: path).removing(entry, force: true).text == #"{"x": 1}"#)
  }

  @Test("an mcpServers emptied by removing reminders goes too, so add then remove gives other keys back as they were")
  func emptiedServersGo() throws {
    for original in [#"{"keep":1}"#, "{\n  \"keep\": 1\n}\n", #"{"a": 1, "b": [2]}"#] {
      let added = try #require(try MCPConfigDocument(original, path: path).adding(entry, force: false).text)
      let removed = try MCPConfigDocument(added, path: path).removing(entry, force: false)
      #expect(removed.text == original)
      #expect(!removed.leavesNothing)
    }
    let first = #"{"mcpServers": {"reminders": {"command": "x"}}, "theme": "dark"}"#
    #expect(try MCPConfigDocument(first, path: path).removing(entry, force: true).text == #"{"theme": "dark"}"#)
    // There's no telling an empty table that was already there from one setup added; neither configures anything.
    let emptyTable = "{\n  \"mcpServers\": {},\n  \"theme\": \"dark\"\n}"
    let filled = try #require(try MCPConfigDocument(emptyTable, path: path).adding(entry, force: false).text)
    #expect(
      try MCPConfigDocument(filled, path: path).removing(entry, force: false).text == "{\n  \"theme\": \"dark\"\n}")
    // Two mcpServers keys can't be spliced; the file is rendered whole, without either.
    let twice = #"{"mcpServers": {}, "theme": "dark", "mcpServers": {"reminders": {"command": "x"}}}"#
    let rendered = try #require(try MCPConfigDocument(twice, path: path).removing(entry, force: true).text)
    #expect(!rendered.contains("reminders"))
    #expect(rendered.contains("theme"))
  }

  @Test("removing the last thing in the file says nothing is left; other servers or keys keep it")
  func leavesNothing() throws {
    let only = #"{"mcpServers": {"reminders": {"command": "x"}}}"#
    #expect(try MCPConfigDocument(only, path: path).removing(entry, force: true).leavesNothing)
    let withKey = #"{"mcpServers": {"reminders": {"command": "x"}}, "theme": "dark"}"#
    #expect(try !MCPConfigDocument(withKey, path: path).removing(entry, force: true).leavesNothing)
    let withServer = #"{"mcpServers": {"reminders": {"command": "x"}, "a": {"command": "a"}}}"#
    #expect(try !MCPConfigDocument(withServer, path: path).removing(entry, force: true).leavesNothing)
    #expect(try !MCPConfigDocument(nil, path: path).removing(entry, force: true).leavesNothing)
  }

  @Test("a duplicated reminders key is rewritten whole rather than half-edited")
  func duplicateKey() throws {
    let duplicated = #"{"mcpServers": {"reminders": {"command": "x"}, "reminders": {"command": "y"}}}"#
    let removed = try #require(try MCPConfigDocument(duplicated, path: path).removing(entry, force: true).text)
    #expect(!removed.contains("reminders"))
  }

  @Test("invalid JSON is refused with the line and column; so are misshapen files")
  func invalid() {
    do {
      _ = try MCPConfigDocument("{\n  \"mcpServers\": {\n    \"a\": {},\n  }\n}\n", path: path)
      Issue.record("expected an error")
    } catch {
      #expect(error.code == .configInvalid)
      #expect(error.message.hasPrefix("\(path) isn't valid JSON (line 4, column 3"))
      #expect(error.suggestion?.contains("left unchanged") == true)
    }
    #expect(code { _ = try MCPConfigDocument("[]", path: path) } == .configInvalid)
    #expect(code { _ = try MCPConfigDocument(#"{"mcpServers": []}"#, path: path) } == .configInvalid)
  }
}
