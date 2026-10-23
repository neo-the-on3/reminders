import MCP
import RemindersCore

/// The tools `reminders --mcp` offers. Each mirrors a CLI command and takes the same inputs.
public enum ReminderTool: String, CaseIterable, Sendable {
  case lists = "reminders_lists"
  case list = "reminders_list"
  case createList = "reminders_create_list"
  case deleteList = "reminders_delete_list"
  case add = "reminders_add"
  case complete = "reminders_complete"
  case delete = "reminders_delete"
  case update = "reminders_update"
  case sections = "reminders_sections"
  case createSection = "reminders_create_section"
  case deleteSection = "reminders_delete_section"
  case move = "reminders_move"
  case today = "reminders_today"
  case overdue = "reminders_overdue"
  case upcoming = "reminders_upcoming"
  case search = "reminders_search"

  /// The tool as `tools/list` describes it.
  public var definition: Tool {
    Tool(
      name: rawValue, title: title, description: summary, inputSchema: inputSchema, annotations: annotations,
      outputSchema: outputSchema)
  }

  /// Section tools exist so clients see the whole tool set, but report NOT_IMPLEMENTED until sections land.
  public var isSectionTool: Bool {
    switch self {
    case .sections, .createSection, .deleteSection, .move: true
    default: false
    }
  }

  // MARK: Descriptions

  var title: String {
    switch self {
    case .lists: "List reminder lists"
    case .list: "Show a list"
    case .createList: "Create a list"
    case .deleteList: "Delete a list"
    case .add: "Add a reminder"
    case .complete: "Complete a reminder"
    case .delete: "Delete a reminder"
    case .update: "Update a reminder"
    case .sections: "List sections"
    case .createSection: "Create a section"
    case .deleteSection: "Delete a section"
    case .move: "Move to a section"
    case .today: "Due today"
    case .overdue: "Overdue"
    case .upcoming: "Upcoming"
    case .search: "Search reminders"
    }
  }

  var summary: String {
    switch self {
    case .lists: "List all reminder lists with their incomplete and overdue counts"
    case .list: "Show the reminders in a list (supports fuzzy name matching)"
    case .createList: "Create a new reminder list (idempotent: an existing list with that exact name is reused)"
    case .deleteList: "Delete a reminder list and all of its reminders"
    case .add: "Add a reminder to a list with optional due date, priority, notes and recurrence"
    case .complete: "Mark a reminder as complete, found by title (fuzzy matched) or ID prefix"
    case .delete: "Delete a reminder, found by title (fuzzy matched) or ID prefix"
    case .update:
      "Update a reminder's title, due date, priority or notes; find it by title (fuzzy matched) or ID prefix"
    case .sections: "List sections in a reminder list (not implemented yet)"
    case .createSection: "Create a section in a list (not implemented yet)"
    case .deleteSection: "Delete a section from a list (not implemented yet)"
    case .move: "Move a reminder to a different section (not implemented yet)"
    case .today: "Show incomplete reminders due today"
    case .overdue: "Show incomplete reminders due before today"
    case .upcoming:
      "Show incomplete reminders due from today through today + N days. Excludes overdue reminders; use "
        + "reminders_overdue for those"
    case .search: "Search incomplete reminders across all lists by title and notes (ignores case)"
    }
  }

  // MARK: Schemas

  private static let listArgument = JSONSchema.string(
    "List name (fuzzy match: 'groceries' finds 'Groceries / Shopping List')")
  private static let titleArgument = JSONSchema.string(
    "Reminder title (fuzzy match: 'sour' finds 'sourdough bread'). Give this or id")
  private static let idArgument = JSONSchema.string("Reminder ID prefix, instead of title. Give this or title")
  private static let dueArgument = JSONSchema.string(
    "Due date: YYYY-MM-DD or natural language ('tomorrow', 'next friday', 'in 3 days')")
  private static let priorityArgument = JSONSchema.oneOf(Priority.allCases.map(\.rawValue), "Priority level")
  private static let sectionArgument = JSONSchema.string("Section name (fuzzy match)")

  var inputSchema: Value {
    switch self {
    case .lists, .today, .overdue:
      return JSONSchema.object()
    case .list:
      return JSONSchema.object(
        ["list": Self.listArgument, "includeCompleted": JSONSchema.boolean("Include completed reminders")],
        required: ["list"])
    case .createList:
      return JSONSchema.object(["name": JSONSchema.string("Name for the new list")], required: ["name"])
    case .deleteList, .sections:
      return JSONSchema.object(["list": Self.listArgument], required: ["list"])
    case .add:
      return JSONSchema.object(
        [
          "list": Self.listArgument, "title": JSONSchema.string("Reminder title"), "section": Self.sectionArgument,
          "due": Self.dueArgument, "priority": Self.priorityArgument, "notes": JSONSchema.string("Reminder notes"),
          "repeat": JSONSchema.string("Recurrence: 'daily', 'weekly', 'every 2 weeks', 'monthly', 'weekly on mon,fri'"),
        ], required: ["list", "title"])
    // `title` or `id` names the reminder. Neither is marked required, because some clients reject a top-level
    // anyOf; the toolbox checks that one of them is given.
    case .complete, .delete:
      return JSONSchema.object(
        ["list": Self.listArgument, "title": Self.titleArgument, "id": Self.idArgument], required: ["list"])
    case .update:
      return JSONSchema.object(
        [
          "list": Self.listArgument, "title": Self.titleArgument, "id": Self.idArgument,
          "newTitle": JSONSchema.string("New title"), "due": Self.dueArgument,
          "clearDue": JSONSchema.boolean("Remove the due date"), "priority": Self.priorityArgument,
          "notes": JSONSchema.string("New notes"),
        ], required: ["list"])
    case .createSection:
      return JSONSchema.object(
        ["list": Self.listArgument, "name": JSONSchema.string("Section name")], required: ["list", "name"])
    case .deleteSection:
      return JSONSchema.object(["list": Self.listArgument, "name": Self.sectionArgument], required: ["list", "name"])
    case .move:
      return JSONSchema.object(
        ["list": Self.listArgument, "title": Self.titleArgument, "toSection": Self.sectionArgument],
        required: ["list", "title", "toSection"])
    case .upcoming:
      return JSONSchema.object([
        "days": JSONSchema.integer("Days to look ahead after today (default: 7; 0 = today only)")
      ])
    case .search:
      return JSONSchema.object(
        ["query": JSONSchema.string("Text to find in titles and notes")], required: ["query"])
    }
  }

  /// The shape of `structuredContent` on success. Section tools have none until they are implemented.
  var outputSchema: Value? {
    switch self {
    case .lists:
      JSONSchema.record(
        ["lists": JSONSchema.array(of: Self.listSchema, "Reminder lists, by title")], required: ["lists"])
    case .list, .today, .overdue, .upcoming, .search:
      JSONSchema.record(
        ["reminders": JSONSchema.array(of: Self.reminderSchema, "Matching reminders")], required: ["reminders"])
    case .createList, .deleteList, .add, .complete, .delete, .update:
      Self.confirmationSchema
    case .sections, .createSection, .deleteSection, .move:
      nil
    }
  }

  private static let listSchema = JSONSchema.record(
    [
      "id": JSONSchema.string("List identifier"), "title": JSONSchema.string("List name"),
      "reminderCount": JSONSchema.integer("Incomplete reminders"),
      "overdueCount": JSONSchema.integer("Incomplete reminders due before today"),
    ], required: ["id", "title", "reminderCount", "overdueCount"])

  private static let reminderSchema = JSONSchema.record(
    [
      "id": JSONSchema.string("Reminder identifier"), "title": JSONSchema.string("Title"),
      "isCompleted": JSONSchema.boolean("Whether it is complete"), "listID": JSONSchema.string("List identifier"),
      "listName": JSONSchema.string("List name"),
      "priority": JSONSchema.oneOf(Priority.allCases.map(\.rawValue), "Priority"),
      "dueDate": JSONSchema.string("Due day (YYYY-MM-DD)", format: "date"),
      "completionDate": JSONSchema.string("When it was completed", format: "date-time"),
      "notes": JSONSchema.string("Notes"), "section": JSONSchema.string("Section name"),
      "isRecurring": JSONSchema.boolean("Whether it repeats"),
      "recurrence": JSONSchema.string("How it repeats, such as 'every 2 weeks'"),
      "flagged": JSONSchema.boolean("Whether it is flagged"),
    ], required: ["id", "title", "isCompleted", "listID", "listName", "priority", "isRecurring"])

  private static let confirmationSchema = JSONSchema.record(
    [
      "message": JSONSchema.string("What was done"),
      "id": JSONSchema.string("Identifier of the created item, when there is one"),
    ], required: ["message"])

  var annotations: Tool.Annotations {
    switch self {
    case .lists, .list, .today, .overdue, .upcoming, .search, .sections:
      Tool.Annotations(readOnlyHint: true, openWorldHint: false)
    case .createList, .createSection:
      Tool.Annotations(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)
    case .add, .move:
      Tool.Annotations(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)
    case .complete, .update:
      Tool.Annotations(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)
    case .delete, .deleteList, .deleteSection:
      Tool.Annotations(readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false)
    }
  }
}
