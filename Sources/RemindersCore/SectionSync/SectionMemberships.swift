import Foundation

/// Which reminder is in which section of a list, as Reminders stores it (the list's
/// `ZMEMBERSHIPSOFREMINDERSINSECTIONSASDATA` JSON, alongside a SHA-512 checksum of those exact bytes).
///
/// Edits keep everything else in the stored JSON untouched: unknown fields, entry order, number formatting.
public struct SectionMemberships: Sendable, Equatable {
  public struct Entry: Hashable, Sendable, Codable {
    public var reminderID: String
    public var sectionID: String

    public init(reminderID: String, sectionID: String) {
      self.reminderID = reminderID
      self.sectionID = sectionID
    }
  }

  /// Schema version written when a list has no membership data yet.
  static let minimumSupportedVersion = 20_230_430

  private var document: PersistedJSON

  /// Reads stored membership data; nil or blank means the list has none yet.
  public init(storedData: String?) throws(RemindersError) {
    guard let storedData, !storedData.allSatisfy(\.isWhitespace) else {
      document = .object([
        ("minimumSupportedVersion", .number(Double(Self.minimumSupportedVersion))), ("memberships", .array([])),
      ])
      return
    }
    do throws(JSONParseError) {
      document = try PersistedJSON(parsing: storedData)
    } catch {
      throw RemindersError(.unknown, "Corrupt section membership data: \(error)")
    }
    guard document.objectValue != nil else {
      throw RemindersError(.unknown, "Corrupt section membership data: not a JSON object")
    }
  }

  private var rawEntries: [PersistedJSON] {
    get { document["memberships"]?.arrayValue ?? [] }
    set { document["memberships"] = .array(newValue) }
  }

  public var entries: [Entry] {
    rawEntries.map {
      Entry(reminderID: $0["memberID"]?.stringValue ?? "", sectionID: $0["groupID"]?.stringValue ?? "")
    }
  }

  /// The section `reminderID` is in, if any.
  public func section(of reminderID: String) -> String? {
    entries.last { $0.reminderID == reminderID }?.sectionID
  }

  /// Each reminder's section; when a reminder is listed more than once, its last entry counts.
  public var sectionsByReminder: [String: String] {
    Dictionary(entries.map { ($0.reminderID, $0.sectionID) }, uniquingKeysWith: { _, last in last })
  }

  /// Puts a reminder in a section, taking it out of any other. Returns false when it was already there.
  /// - Parameters: reminderID, sectionID: dashed upper-case UUIDs.
  @discardableResult
  public mutating func assign(_ reminderID: String, to sectionID: String, at date: Date) -> Bool {
    let isMember = rawEntries.contains {
      $0["memberID"]?.stringValue == reminderID && $0["groupID"]?.stringValue == sectionID
    }
    guard !isMember else { return false }
    rawEntries =
      rawEntries.filter { $0["memberID"]?.stringValue != reminderID } + [
        .object([
          ("memberID", .string(reminderID)), ("groupID", .string(sectionID)),
          ("modifiedOn", .number(date.timeIntervalSinceReferenceDate)),
        ])
      ]
    return true
  }

  /// Takes a reminder out of its section. Returns false when it wasn't in one.
  @discardableResult
  public mutating func remove(_ reminderID: String) -> Bool {
    let remaining = rawEntries.filter { $0["memberID"]?.stringValue != reminderID }
    guard remaining.count != rawEntries.count else { return false }
    rawEntries = remaining
    return true
  }

  /// Takes every reminder out of `sectionID`, as when the section is deleted. Returns false when none was in it.
  @discardableResult
  public mutating func removeAll(inSection sectionID: String) -> Bool {
    let remaining = rawEntries.filter { $0["groupID"]?.stringValue != sectionID }
    guard remaining.count != rawEntries.count else { return false }
    rawEntries = remaining
    return true
  }

  /// The JSON to store: compact, in the original key order.
  public var storedData: String { document.serialized }

  /// Lower-case hex SHA-512 of ``storedData``'s UTF-8 bytes, which Reminders checks before trusting the data.
  public var checksum: String { Self.checksum(of: storedData) }

  static func checksum(of text: String) -> String {
    SHA512Digest.hex(of: text.utf8)
  }

  /// Whether `stored` has a checksum that doesn't match its data. Such data is never edited: writing a fresh
  /// checksum over it would hide whatever went wrong.
  public static func isCorrupt(_ stored: StoredMemberships) -> Bool {
    guard let data = stored.data, let checksum = stored.checksum, !checksum.isEmpty else { return false }
    return checksum.lowercased() != Self.checksum(of: data)
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
