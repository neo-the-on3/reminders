// Ported from remi src/core/tokenmap.ts and the token-map handling in src/swift/section-helper.swift
// (MIT, Matthew O'Riordan).
//
// The resolution token map is Apple's CRDT-style vector clock for field-level sync. Each syncable
// field has a counter and modificationTime. When a field changes locally its counter must be
// incremented to tell remindd's sync engine "this field has a local change that needs pushing to
// CloudKit". These are pure functions: no side effects, easy to unit test.

/// Field whose counter tracks section-membership changes.
public let membershipTokenField = "membershipsOfRemindersInSectionsChecksum"
/// Field remindd appears to use as the trigger to push the full list record.
public let orderingTokenField = "reminderIDsMergeableOrdering"

/// Parse a token map JSON string. Returns an empty map if the input is nil, empty or invalid.
public func parseTokenMap(_ json: String?) -> TokenMap {
  guard let json, !json.jsTrimmed.isEmpty, let value = try? JSONValue.parse(json), let fields = value.objectValue
  else { return [:] }
  var map: TokenMap = [:]
  for (key, entry) in fields {
    map[key] = TokenMapEntry(
      counter: entry["counter"]?.numberValue.map { Int(exactly: $0) ?? Int($0) } ?? 0,
      modificationTime: entry["modificationTime"]?.numberValue ?? 0)
  }
  return map
}

/// Increment the membership field counter and set its modificationTime.
/// Returns a new map; the input is not mutated (value semantics).
public func incrementMembershipCounter(_ tokenMap: TokenMap, timestamp: Double) -> TokenMap {
  var updated = tokenMap
  let currentCounter = updated[membershipTokenField]?.counter ?? 0
  updated[membershipTokenField] = TokenMapEntry(counter: currentCounter + 1, modificationTime: timestamp)
  return updated
}

/// Serialise a token map to compact JSON with sorted keys.
///
/// Note: remi's `JSON.stringify(map, Object.keys(map).sort())` uses an array replacer, which also
/// filters *nested* keys and therefore drops `counter`/`modificationTime`. That helper is unused
/// upstream; this port keeps the entries intact.
public func serializeTokenMap(_ tokenMap: TokenMap) -> String {
  JSONValue.object(tokenMap.keys.sorted().map { ($0, tokenMap[$0]!.jsonValue) }).stringified()
}

/// Current counter for the membership field (0 if absent).
public func getMembershipCounter(_ tokenMap: TokenMap) -> Int {
  tokenMap[membershipTokenField]?.counter ?? 0
}

/// Apply the token-map update remi performs when writing section memberships
/// (`writeMembershipSync` in section-helper.swift) to the raw `ZRESOLUTIONTOKENMAP_V3_JSONDATA` value.
///
/// - Entries live inside the top-level `"map"` object.
/// - `membershipsOfRemindersInSectionsChecksum` gets `counter + 1`, the new modificationTime and a
///   `replicaID` (the existing one is preserved; otherwise `newReplicaID` is used).
/// - `reminderIDsMergeableOrdering`, if present with a counter, is also incremented. Without this,
///   membership-only changes don't propagate to other devices.
///
/// Unknown fields are preserved. Invalid or empty input starts from an empty object.
/// - Returns: the updated token map; serialise with `stringified()` (key order is up to the caller —
///   the Apple layer sorts keys, matching `JSONSerialization` with `.sortedKeys`).
public func applyMembershipWrite(
  toTokenMapJSON json: String?, coreDataTimestamp: Double, newReplicaID: String
) -> JSONValue {
  var tokenMap: JSONValue = .object([])
  if let json, let parsed = try? JSONValue.parse(json), parsed.objectValue != nil {
    tokenMap = parsed
  }

  var map: JSONValue = tokenMap["map"].flatMap { $0.objectValue != nil ? $0 : nil } ?? .object([])

  var currentCounter = 0
  var replicaID = newReplicaID
  if let existing = map[membershipTokenField], existing.objectValue != nil {
    if let counter = existing["counter"]?.numberValue, let intCounter = Int(exactly: counter) {
      currentCounter = intCounter
    }
    if let existingReplica = existing["replicaID"]?.stringValue {
      replicaID = existingReplica
    }
  }
  map[membershipTokenField] = .object([
    ("counter", .number(Double(currentCounter + 1))),
    ("modificationTime", .number(coreDataTimestamp)),
    ("replicaID", .string(replicaID)),
  ])

  if var ordering = map[orderingTokenField], ordering.objectValue != nil,
    let counter = ordering["counter"]?.numberValue, let intCounter = Int(exactly: counter)
  {
    ordering["counter"] = .number(Double(intCounter + 1))
    ordering["modificationTime"] = .number(coreDataTimestamp)
    map[orderingTokenField] = ordering
  }

  tokenMap["map"] = map
  return tokenMap
}

extension JSONValue {
  /// A copy with every object's keys sorted (recursively), like `JSONSerialization`'s `.sortedKeys`.
  public var sortingKeys: JSONValue {
    switch self {
    case .array(let items): return .array(items.map(\.sortingKeys))
    case .object(let fields):
      return .object(
        fields.sorted { $0.0.utf16.lexicographicallyPrecedes($1.0.utf16) }.map { ($0.0, $0.1.sortingKeys) })
    default: return self
    }
  }
}
