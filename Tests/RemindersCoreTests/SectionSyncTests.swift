import Foundation
import Testing

@testable import RemindersCore

private let blob =
  #"{"minimumSupportedVersion":20230430,"memberships":[{"memberID":"M1","groupID":"G1","modifiedOn":1}]}"#

@Suite("Section memberships")
struct SectionMembershipsTests {
  @Test("a list without membership data gets a fresh document on first assignment")
  func firstAssignment() throws {
    for stored in [nil, "", "   "] as [String?] {
      var memberships = try SectionMemberships(storedData: stored)
      #expect(memberships.entries.isEmpty)
      let changed = memberships.assign("M1", to: "G1", at: Date(timeIntervalSinceReferenceDate: 1.5))
      #expect(changed)
      #expect(
        memberships.storedData
          == #"{"minimumSupportedVersion":20230430,"memberships":[{"memberID":"M1","groupID":"G1","modifiedOn":1.5}]}"#)
    }
  }

  @Test("assigning to the current section changes nothing")
  func idempotent() throws {
    var memberships = try SectionMemberships(storedData: blob)
    let changed = memberships.assign("M1", to: "G1", at: .now)
    #expect(!changed)
    #expect(memberships.storedData == blob)
  }

  @Test("moving appends the new entry and keeps other entries, order, numbers and unknown fields")
  func move() throws {
    var memberships = try SectionMemberships(
      storedData:
        #"{"minimumSupportedVersion":20230430,"memberships":[{"memberID":"M1","groupID":"G1","modifiedOn":783456789.123456},{"memberID":"M2","groupID":"G1","modifiedOn":5,"extra":true}],"future":1}"#
    )
    memberships.assign("M1", to: "G2", at: Date(timeIntervalSinceReferenceDate: 9))
    #expect(
      memberships.storedData
        == #"{"minimumSupportedVersion":20230430,"memberships":[{"memberID":"M2","groupID":"G1","modifiedOn":5,"extra":true},{"memberID":"M1","groupID":"G2","modifiedOn":9}],"future":1}"#
    )
    #expect(memberships.section(of: "M1") == "G2")
    #expect(memberships.entries.map(\.reminderID) == ["M2", "M1"])
  }

  @Test("removing a reminder, or reporting there was nothing to remove")
  func removal() throws {
    var memberships = try SectionMemberships(storedData: blob)
    let removedUnknown = memberships.remove("M9")
    let removedMember = memberships.remove("M1")
    #expect(!removedUnknown)
    #expect(removedMember)
    #expect(memberships.storedData == #"{"minimumSupportedVersion":20230430,"memberships":[]}"#)
  }

  @Test("corrupt data is reported, never overwritten")
  func corrupt() {
    #expect(throws: RemindersError.self) { try SectionMemberships(storedData: "{oops") }
    #expect(throws: RemindersError.self) { try SectionMemberships(storedData: "[1]") }
  }

  @Test("the checksum is SHA-512 of the exact stored bytes")
  func checksum() throws {
    let memberships = try SectionMemberships(storedData: blob)
    #expect(memberships.checksum == SHA512Digest.hex(of: blob.utf8))
    #expect(memberships.checksum.count == 128)
  }

  @Test("Core Data identifiers convert to UUIDs")
  func uuid() {
    #expect(UUID(compactHex: "0123456789abcdef0123456789abcdef")?.uuidString == "01234567-89AB-CDEF-0123-456789ABCDEF")
    #expect(UUID(compactHex: "0123") == nil)
  }
}

@Suite("Resolution token map")
struct ResolutionTokenMapTests {
  @Test("missing or unreadable data starts from scratch")
  func fromScratch() {
    for stored in [nil, "", "garbage", "[1,2]"] as [String?] {
      var map = ResolutionTokenMap(storedData: stored)
      #expect(map.counter(of: .memberships) == nil)
      map.recordMembershipChange(at: Date(timeIntervalSinceReferenceDate: 800_000_000.5), newReplicaID: "R1")
      #expect(
        map.storedData
          == #"{"map":{"membershipsOfRemindersInSectionsChecksum":{"counter":1,"modificationTime":800000000.5,"replicaID":"R1"}}}"#
      )
    }
  }

  @Test("bumps the membership and ordering counters, keeping replica IDs and other fields")
  func increments() {
    var map = ResolutionTokenMap(
      storedData: #"""
        {"map":{"membershipsOfRemindersInSectionsChecksum":{"counter":4,"modificationTime":1,"replicaID":"KEEP"},
        "reminderIDsMergeableOrdering":{"counter":9,"modificationTime":2,"replicaID":"ORD"},
        "name":{"counter":1,"modificationTime":3}},"version":2}
        """#)
    map.recordMembershipChange(at: Date(timeIntervalSinceReferenceDate: 10), newReplicaID: "NEW")
    #expect(map.counter(of: .memberships) == 5)
    #expect(map.counter(of: .ordering) == 10)
    #expect(map.replicaID(of: .memberships) == "KEEP")
    #expect(
      map.storedData
        == #"{"map":{"membershipsOfRemindersInSectionsChecksum":{"counter":5,"modificationTime":10,"replicaID":"KEEP"},"name":{"counter":1,"modificationTime":3},"reminderIDsMergeableOrdering":{"counter":10,"modificationTime":10,"replicaID":"ORD"}},"version":2}"#
    )
  }

  @Test("never creates an ordering entry")
  func noOrdering() {
    var map = ResolutionTokenMap(storedData: #"{"map":{}}"#)
    map.recordMembershipChange(at: .now, newReplicaID: "NEW")
    #expect(map.counter(of: .ordering) == nil)
  }
}

@Suite("SHA-512")
struct SHA512DigestTests {
  static let vectors: [(String, String)] = [
    (
      "",
      "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"
    ),
    (
      "abc",
      "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"
    ),
    (
      "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
      "8e959b75dae313da8cf4f72814fc143f8f7779c6eb9f7fa17299aeadb6889018501d289e4900f7e4331b99dec4b5433ac7d329eeb6dd26545e96e55b874be909"
    ),
    (
      "The quick brown fox jumps over the lazy dog",
      "07e547d9586f6a73f73fbac0435ed76951218fb7d0c8d788a309d785436bbb642e93a252a954f23912547d1e8a3b5ed6e1bfd7097821233fa0538f3db854fee6"
    ),
  ]

  @Test("matches the FIPS 180-4 vectors on this platform and in the portable implementation")
  func vectors() {
    for (input, digest) in Self.vectors {
      #expect(SHA512Digest.hex(of: input.utf8) == digest)
      #expect(SHA512Digest.hexString(PortableSHA512.hash(Array(input.utf8))) == digest)
    }
  }

  @Test("the portable implementation handles block boundaries and multi-byte UTF-8")
  func boundaries() {
    let inputs = [111, 112, 127, 128, 129, 1000].map { String(repeating: "a", count: $0) } + ["Ünïcødé 😀"]
    for input in inputs {
      #expect(SHA512Digest.hexString(PortableSHA512.hash(Array(input.utf8))) == SHA512Digest.hex(of: input.utf8))
    }
  }
}

@Suite("Persisted JSON")
struct PersistedJSONTests {
  @Test("round-trips compactly, keeping key order, unknown fields and escapes")
  func roundTrip() throws {
    let text = #"{"b":1,"a":[true,false,null],"s":"line\nbreak \"q\" \\ \u0001 é/😀","n":-0.5}"#
    #expect(
      try PersistedJSON(parsing: text).serialized
        == #"{"b":1,"a":[true,false,null],"s":"line\nbreak \"q\" \\ \u0001 é/😀","n":-0.5}"#)
  }

  @Test("prints integral numbers without a fraction and uses exponents only for extreme magnitudes")
  func numbers() {
    let cases: [(Double, String)] = [
      (20_230_430, "20230430"), (783_456_789.123456, "783456789.123456"), (0.000001, "0.000001"), (1e-7, "1e-7"),
      (1e21, "1e+21"), (123e18, "123000000000000000000"), (-0.0, "0"), (1.5, "1.5"),
    ]
    for (value, text) in cases {
      #expect(PersistedJSON.format(value) == text)
    }
  }

  @Test("rejects what strict JSON rejects")
  func strictness() {
    for text in ["", "{", "[1,]", "{\"a\":01}", "'x'", "{\"a\":1} x", "\"\\x\""] {
      #expect(throws: JSONParseError.self) { try PersistedJSON(parsing: text) }
    }
  }
}
