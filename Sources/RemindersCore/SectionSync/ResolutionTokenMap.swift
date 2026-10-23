import Foundation

/// A list's resolution token map (`ZRESOLUTIONTOKENMAP_V3_JSONDATA`): per-field vector clocks that tell Reminders'
/// sync engine which fields changed locally and need pushing to iCloud.
///
/// Each field under `"map"` has a `counter`, a `modificationTime` (seconds since 2001) and a `replicaID`.
public struct ResolutionTokenMap: Sendable, Equatable {
  public enum Field: String, Sendable, CaseIterable {
    /// Changes whenever section memberships change.
    case memberships = "membershipsOfRemindersInSectionsChecksum"
    /// Bumping it makes Reminders push the whole list record, without which membership-only changes don't reach
    /// other devices.
    case ordering = "reminderIDsMergeableOrdering"
  }

  private var document: PersistedJSON

  /// Reads a stored token map. Missing or unreadable data starts an empty one (as Reminders does).
  public init(storedData: String?) {
    if let storedData, let parsed = try? PersistedJSON(parsing: storedData), parsed.objectValue != nil {
      document = parsed
    } else {
      document = .object([])
    }
  }

  private var fields: PersistedJSON {
    get { document["map"].flatMap { $0.objectValue != nil ? $0 : nil } ?? .object([]) }
    set { document["map"] = newValue }
  }

  /// The field's counter, or nil when it has none.
  public func counter(of field: Field) -> Int? {
    fields[field.rawValue]?["counter"]?.numberValue.flatMap { Int(exactly: $0) }
  }

  /// The field's replica identifier, if it has one.
  public func replicaID(of field: Field) -> String? {
    fields[field.rawValue]?["replicaID"]?.stringValue
  }

  /// Records a local change of section memberships at `date`: the membership counter goes up by one (created with
  /// `newReplicaID` when absent) and, when the list has an ordering counter, so does that. Unknown fields are kept.
  public mutating func recordMembershipChange(at date: Date, newReplicaID: String) {
    let timestamp = PersistedJSON.number(date.timeIntervalSinceReferenceDate)
    fields[Field.memberships.rawValue] = .object([
      ("counter", .number(Double((counter(of: .memberships) ?? 0) + 1))),
      ("modificationTime", timestamp),
      ("replicaID", .string(replicaID(of: .memberships) ?? newReplicaID)),
    ])
    if let ordering = counter(of: .ordering), var entry = fields[Field.ordering.rawValue] {
      entry["counter"] = .number(Double(ordering + 1))
      entry["modificationTime"] = timestamp
      fields[Field.ordering.rawValue] = entry
    }
  }

  /// The JSON to store: compact, keys sorted at every level.
  public var storedData: String { document.sortingKeys.serialized }
}

extension PersistedJSON {
  /// A copy with every object's keys sorted, recursively.
  var sortingKeys: PersistedJSON {
    switch self {
    case .array(let items): .array(items.map(\.sortingKeys))
    case .object(let fields): .object(fields.sorted { $0.0 < $1.0 }.map { ($0.0, $0.1.sortingKeys) })
    default: self
    }
  }
}
