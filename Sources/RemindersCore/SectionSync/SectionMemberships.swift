import Foundation

/// Which reminder is in which section of a list, as Reminders stores it (the list's
/// `ZMEMBERSHIPSOFREMINDERSINSECTIONSASDATA` JSON).
///
/// Read-only: memberships only ever change through Reminders itself (see ``SectionStore/assign(reminderID:to:in:)``),
/// which keeps the data, its checksum and iCloud sync consistent.
public struct SectionMemberships: Sendable, Equatable {
  public struct Entry: Hashable, Sendable, Codable {
    public var reminderID: String
    public var sectionID: String
    /// When the membership was set, in seconds since 2001, if recorded.
    public var modifiedOn: Double?

    public init(reminderID: String, sectionID: String, modifiedOn: Double? = nil) {
      self.reminderID = reminderID
      self.sectionID = sectionID
      self.modifiedOn = modifiedOn
    }
  }

  public let entries: [Entry]

  /// Reads stored membership data; nil or blank means the list has none yet.
  public init(storedData: String?) throws(RemindersError) {
    guard let storedData, !storedData.allSatisfy(\.isWhitespace) else {
      entries = []
      return
    }
    let document: PersistedJSON
    do throws(JSONParseError) {
      document = try PersistedJSON(parsing: storedData)
    } catch {
      throw RemindersError(.unknown, "Corrupt section membership data: \(error)")
    }
    guard document.objectValue != nil else {
      throw RemindersError(.unknown, "Corrupt section membership data: not a JSON object")
    }
    entries = (document["memberships"]?.arrayValue ?? []).map {
      Entry(
        reminderID: $0["memberID"]?.stringValue ?? "", sectionID: $0["groupID"]?.stringValue ?? "",
        modifiedOn: $0["modifiedOn"]?.numberValue)
    }
  }

  public init(entries: [Entry]) {
    self.entries = entries
  }

  /// The section `reminderID` is in, if any.
  public func section(of reminderID: String) -> String? {
    sectionsByReminder[reminderID]
  }

  /// Each reminder's section. When a reminder is listed more than once, the entry modified last counts, as in
  /// Reminders' own merge; between entries with the same or no time, the later one in the data.
  public var sectionsByReminder: [String: String] {
    Dictionary(current.map { ($0.reminderID, $0.sectionID) }, uniquingKeysWith: { _, last in last })
  }

  /// The entry that counts for each reminder (see ``sectionsByReminder``), in the order reminders first appear.
  public var current: [Entry] {
    var newest: [String: Entry] = [:]
    var order: [String] = []
    for entry in entries {
      guard let previous = newest[entry.reminderID] else {
        newest[entry.reminderID] = entry
        order.append(entry.reminderID)
        continue
      }
      if (previous.modifiedOn ?? -.infinity) <= (entry.modifiedOn ?? -.infinity) { newest[entry.reminderID] = entry }
    }
    return order.compactMap { newest[$0] }
  }
}

extension StoredMemberships {
  /// Membership data in Reminders' format holding `entries`, for sources that hand memberships over as objects
  /// rather than as the stored JSON.
  public init(entries: [SectionMemberships.Entry]) {
    struct Membership: Encodable {
      var memberID: String
      var groupID: String
      var modifiedOn: Double?
    }
    struct Document: Encodable {
      var minimumSupportedVersion = 20_230_430
      var memberships: [Membership]
    }
    let document = Document(
      memberships: entries.map { Membership(memberID: $0.reminderID, groupID: $0.sectionID, modifiedOn: $0.modifiedOn) }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    self.init(data: (try? encoder.encode(document)).flatMap { String(data: $0, encoding: .utf8) })
  }
}

extension UUID {
  /// A UUID from its 32 hex digits without dashes, as Core Data stores identifiers.
  public init?(compactHex hex: String) {
    guard hex.utf8.count == 32 else { return nil }
    let digits = Array(hex)
    let groups = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(digits[$0]) }
    self.init(uuidString: groups.joined(separator: "-"))
  }
}
