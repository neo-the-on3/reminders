// Pure section-membership logic ported from remi src/core/membership.ts.

import Testing

@testable import RemiCore

@Suite("membership")
struct MembershipTests {
  @Test("hexToUUID formats 32 hex characters as an upper-case dashed UUID")
  func hexToUUIDFormat() {
    #expect(hexToUUID("0123456789abcdef0123456789abcdef") == "01234567-89AB-CDEF-0123-456789ABCDEF")
  }

  @Test("Core Data timestamps count from 2001-01-01")
  func coreDataEpoch() {
    #expect(coreDataTimestamp(unixTime: 978_307_200) == 0)
    #expect(coreDataTimestamp(unixTime: 1_800_000_000.25) == 821_692_800.25)
  }

  @Test("first assignment creates a blob with minimumSupportedVersion")
  func firstAssignment() throws {
    for current in [nil, "", "   "] as [String?] {
      let change = try assignMembership(currentData: current, memberID: "M1", groupID: "G1", timestamp: 1.5)
      #expect(
        change
          == .write(
            #"{"minimumSupportedVersion":20230430,"memberships":[{"memberID":"M1","groupID":"G1","modifiedOn":1.5}]}"#))
    }
  }

  @Test("assigning to the current section is a no-op")
  func idempotent() throws {
    let blob = #"{"minimumSupportedVersion":20230430,"memberships":[{"memberID":"M1","groupID":"G1","modifiedOn":1}]}"#
    #expect(try assignMembership(currentData: blob, memberID: "M1", groupID: "G1", timestamp: 2) == .unchanged)
  }

  @Test("reassigning moves the reminder, appends, and preserves other entries, order and unknown fields")
  func move() throws {
    let blob =
      #"{"minimumSupportedVersion":20230430,"memberships":[{"memberID":"M1","groupID":"G1","modifiedOn":783456789.123456},{"memberID":"M2","groupID":"G1","modifiedOn":5,"extra":true}],"future":1}"#
    let change = try assignMembership(currentData: blob, memberID: "M1", groupID: "G2", timestamp: 9)
    #expect(
      change
        == .write(
          #"{"minimumSupportedVersion":20230430,"memberships":[{"memberID":"M2","groupID":"G1","modifiedOn":5,"extra":true},{"memberID":"M1","groupID":"G2","modifiedOn":9}],"future":1}"#
        ))
  }

  @Test("removal drops the reminder or reports no change")
  func removal() throws {
    let blob = #"{"minimumSupportedVersion":20230430,"memberships":[{"memberID":"M1","groupID":"G1","modifiedOn":1}]}"#
    #expect(
      try removeMembership(currentData: blob, memberID: "M1")
        == .write(#"{"minimumSupportedVersion":20230430,"memberships":[]}"#))
    #expect(try removeMembership(currentData: blob, memberID: "M9") == .unchanged)
    #expect(try removeMembership(currentData: nil, memberID: "M1") == .unchanged)
  }

  @Test("decodes memberships into reminder/section pairs")
  func decode() throws {
    let blob =
      #"{"memberships":[{"memberID":"M1","groupID":"G1","modifiedOn":1},{"memberID":"M2","groupID":"G2","modifiedOn":1}]}"#
    #expect(
      try decodeMemberships(blob)
        == MembershipData(memberships: [
          MembershipEntry(reminderID: "M1", sectionID: "G1"), MembershipEntry(reminderID: "M2", sectionID: "G2"),
        ]))
    #expect(try decodeMemberships(nil) == MembershipData(memberships: []))
  }

  @Test("corrupt blobs raise a remi error instead of being overwritten")
  func corrupt() {
    #expect(throws: RemiCommandError.self) {
      try assignMembership(currentData: "{oops", memberID: "M1", groupID: "G1", timestamp: 1)
    }
  }

  @Test("checksum of the written blob is what remindd expects (SHA-512 of the exact bytes)")
  func checksumOfBlob() throws {
    guard case .write(let json) = try assignMembership(currentData: nil, memberID: "M", groupID: "G", timestamp: 1)
    else {
      Issue.record("expected a write")
      return
    }
    #expect(computeMembershipChecksum(json) == hexString(PortableSHA512.hash(Array(json.utf8))))
  }
}
