// Ported from remi src/core/membership.ts (MIT, Matthew O'Riordan).
//
// Pure part of section-membership orchestration. The Apple layer reads the current
// ZMEMBERSHIPSOFREMINDERSINSECTIONSASDATA blob, this file computes the new blob, and the Apple layer
// writes data + checksum + token map atomically and triggers sync.
//
// The blob is edited as an order-preserving ``JSONValue`` and re-serialised compactly, exactly as
// `JSON.stringify(JSON.parse(blob))` would, because remindd checksums the exact bytes.

/// Schema version remi writes when creating a membership blob from scratch.
public let membershipMinimumSupportedVersion = 20_230_430

/// Convert a 32-character hex UUID to dashed upper-case form (8-4-4-4-12).
public func hexToUUID(_ hex: String) -> String {
  let h = Array(hex.uppercased())
  func slice(_ from: Int, _ to: Int?) -> String {
    let lower = min(from, h.count)
    let upper = min(to ?? h.count, h.count)
    return lower < upper ? String(h[lower..<upper]) : ""
  }
  return "\(slice(0, 8))-\(slice(8, 12))-\(slice(12, 16))-\(slice(16, 20))-\(slice(20, nil))"
}

/// Core Data timestamp: seconds since 2001-01-01 00:00:00 UTC, from a Unix time in seconds.
public func coreDataTimestamp(unixTime: Double) -> Double {
  unixTime - 978_307_200
}

/// Result of a membership edit.
public enum MembershipChange: Equatable, Sendable {
  /// Nothing to write (already in that state).
  case unchanged
  /// Write this exact JSON string to the database.
  case write(String)
}

/// Compute the blob after assigning `memberID` to section `groupID` (move semantics, idempotent).
/// - Parameters:
///   - currentData: current blob text (nil/blank when the list has no memberships yet).
///   - memberID, groupID: dashed upper-case UUIDs (see ``hexToUUID(_:)``).
///   - timestamp: Core Data timestamp for `modifiedOn`.
public func assignMembership(
  currentData: String?, memberID: String, groupID: String, timestamp: Double
) throws(RemiCommandError) -> MembershipChange {
  let newEntry: JSONValue = .object([
    ("memberID", .string(memberID)), ("groupID", .string(groupID)), ("modifiedOn", .number(timestamp)),
  ])

  guard let currentData, !currentData.jsTrimmed.isEmpty else {
    let blob: JSONValue = .object([
      ("minimumSupportedVersion", .number(Double(membershipMinimumSupportedVersion))),
      ("memberships", .array([newEntry])),
    ])
    return .write(blob.stringified())
  }

  var blob = try parseMembershipBlob(currentData)
  let memberships = blob["memberships"]?.arrayValue ?? []

  // Idempotent: already assigned to this section
  if memberships.contains(where: { $0["memberID"]?.stringValue == memberID && $0["groupID"]?.stringValue == groupID }) {
    return .unchanged
  }

  // Remove any existing assignment (move semantics), then append
  var updated = memberships.filter { $0["memberID"]?.stringValue != memberID }
  updated.append(newEntry)
  blob["memberships"] = .array(updated)
  return .write(blob.stringified())
}

/// Compute the blob after removing `memberID` from whatever section it is in.
public func removeMembership(currentData: String?, memberID: String) throws(RemiCommandError) -> MembershipChange {
  guard let currentData, !currentData.jsTrimmed.isEmpty else { return .unchanged }
  var blob = try parseMembershipBlob(currentData)
  let memberships = blob["memberships"]?.arrayValue ?? []
  let updated = memberships.filter { $0["memberID"]?.stringValue != memberID }
  if updated.count == memberships.count { return .unchanged }
  blob["memberships"] = .array(updated)
  return .write(blob.stringified())
}

/// Decode the blob into the public reminder → section mapping.
public func decodeMemberships(_ data: String?) throws(RemiCommandError) -> MembershipData {
  guard let data, !data.jsTrimmed.isEmpty else { return MembershipData(memberships: []) }
  let blob = try parseMembershipBlob(data)
  let entries = (blob["memberships"]?.arrayValue ?? []).map {
    MembershipEntry(reminderID: $0["memberID"]?.stringValue ?? "", sectionID: $0["groupID"]?.stringValue ?? "")
  }
  return MembershipData(memberships: entries)
}

private func parseMembershipBlob(_ text: String) throws(RemiCommandError) -> JSONValue {
  do throws(JSONParseError) {
    let value = try JSONValue.parse(text)
    guard value.objectValue != nil else {
      throw JSONParseError(offset: 0, reason: "Membership data is not a JSON object")
    }
    return value
  } catch {
    throw RemiCommandError(.unknown, "Corrupt section membership data: \(error.description)")
  }
}
