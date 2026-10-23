import MCP

/// Builders for the JSON Schema (draft 2020-12 subset) that MCP clients see in `tools/list`.
enum JSONSchema {
  /// An object with the given properties, of which `required` must be present, and no others.
  static func object(_ properties: [String: Value] = [:], required: [String] = []) -> Value {
    var schema: [String: Value] = [
      "type": "object", "properties": .object(properties), "additionalProperties": false,
    ]
    if !required.isEmpty { schema["required"] = .array(required.sorted().map { .string($0) }) }
    return .object(schema)
  }

  static func string(_ description: String, format: String? = nil) -> Value {
    var schema: [String: Value] = ["type": "string", "description": .string(description)]
    if let format { schema["format"] = .string(format) }
    return .object(schema)
  }

  static func oneOf(_ values: [String], _ description: String) -> Value {
    ["type": "string", "enum": .array(values.map { .string($0) }), "description": .string(description)]
  }

  static func boolean(_ description: String) -> Value {
    ["type": "boolean", "description": .string(description)]
  }

  static func integer(_ description: String) -> Value {
    ["type": "integer", "description": .string(description)]
  }

  static func array(of items: Value, _ description: String) -> Value {
    ["type": "array", "items": items, "description": .string(description)]
  }

  /// Like ``object(_:required:)`` but open to further properties, for results that may grow fields.
  static func record(_ properties: [String: Value], required: [String]) -> Value {
    [
      "type": "object", "properties": .object(properties),
      "required": .array(required.sorted().map { .string($0) }),
    ]
  }

  /// The property names an object schema allows.
  static func propertyNames(of schema: Value) -> Set<String> {
    guard let properties = schema.objectValue?["properties"]?.objectValue else { return [] }
    return Set(properties.keys)
  }

  /// The property names an object schema requires.
  static func requiredNames(of schema: Value) -> [String] {
    schema.objectValue?["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
  }
}
