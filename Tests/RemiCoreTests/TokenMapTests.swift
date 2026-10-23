// Ported from remi tests/unit/tokenmap.test.ts, plus the section-helper token-map update.

import Testing

@testable import RemiCore

@Suite("tokenmap")
struct TokenMapTests {
  // MARK: parseTokenMap

  @Test("returns empty map for nil input")
  func nilInput() { #expect(parseTokenMap(nil) == [:]) }

  @Test("returns empty map for empty string")
  func emptyInput() { #expect(parseTokenMap("") == [:]) }

  @Test("returns empty map for invalid JSON")
  func invalidInput() { #expect(parseTokenMap("not json") == [:]) }

  @Test("parses valid token map JSON")
  func validInput() {
    let json =
      #"{"displayName":{"counter":2,"modificationTime":733456700},"membershipsOfRemindersInSectionsChecksum":{"counter":5,"modificationTime":733456789}}"#
    let result = parseTokenMap(json)
    #expect(result["displayName"] == TokenMapEntry(counter: 2, modificationTime: 733_456_700))
    #expect(
      result["membershipsOfRemindersInSectionsChecksum"] == TokenMapEntry(counter: 5, modificationTime: 733_456_789))
  }

  // MARK: incrementMembershipCounter

  @Test("creates entry if not present")
  func createsEntry() {
    let result = incrementMembershipCounter([:], timestamp: 1000)
    #expect(result["membershipsOfRemindersInSectionsChecksum"] == TokenMapEntry(counter: 1, modificationTime: 1000))
  }

  @Test("increments existing counter")
  func increments() {
    let map: TokenMap = ["membershipsOfRemindersInSectionsChecksum": .init(counter: 5, modificationTime: 500)]
    let result = incrementMembershipCounter(map, timestamp: 1000)
    #expect(result["membershipsOfRemindersInSectionsChecksum"] == TokenMapEntry(counter: 6, modificationTime: 1000))
  }

  @Test("preserves other fields")
  func preservesOthers() {
    let map: TokenMap = [
      "displayName": .init(counter: 2, modificationTime: 700),
      "membershipsOfRemindersInSectionsChecksum": .init(counter: 3, modificationTime: 800),
    ]
    let result = incrementMembershipCounter(map, timestamp: 1000)
    #expect(result["displayName"] == TokenMapEntry(counter: 2, modificationTime: 700))
    #expect(result["membershipsOfRemindersInSectionsChecksum"]?.counter == 4)
  }

  @Test("does not mutate the input")
  func noMutation() {
    let map: TokenMap = ["membershipsOfRemindersInSectionsChecksum": .init(counter: 1, modificationTime: 500)]
    let original = map
    _ = incrementMembershipCounter(map, timestamp: 1000)
    #expect(map == original)
  }

  // MARK: getMembershipCounter

  @Test("returns 0 for empty map")
  func counterEmpty() { #expect(getMembershipCounter([:]) == 0) }

  @Test("returns current counter value")
  func counterValue() {
    #expect(
      getMembershipCounter(["membershipsOfRemindersInSectionsChecksum": .init(counter: 7, modificationTime: 0)]) == 7)
  }

  // MARK: serializeTokenMap

  @Test("produces valid JSON")
  func serializeValid() throws {
    let map: TokenMap = ["b": .init(counter: 1, modificationTime: 0), "a": .init(counter: 2, modificationTime: 0)]
    let json = serializeTokenMap(map)
    #expect(try JSONValue.parse(json).objectValue != nil)
    #expect(json == #"{"a":{"counter":2,"modificationTime":0},"b":{"counter":1,"modificationTime":0}}"#)
  }

  // MARK: applyMembershipWrite (section-helper's writeMembershipSync)

  @Test("starts from scratch for missing or invalid token maps")
  func writeFromScratch() {
    for input in [nil, "", "garbage", "[1,2]"] as [String?] {
      let result = applyMembershipWrite(toTokenMapJSON: input, coreDataTimestamp: 800_000_000.5, newReplicaID: "R1")
      #expect(
        result.sortingKeys.stringified()
          == #"{"map":{"membershipsOfRemindersInSectionsChecksum":{"counter":1,"modificationTime":800000000.5,"replicaID":"R1"}}}"#
      )
    }
  }

  @Test("increments membership and ordering counters, preserving replicaID and other fields")
  func writeIncrements() {
    let existing = #"""
      {"map":{"membershipsOfRemindersInSectionsChecksum":{"counter":4,"modificationTime":1,"replicaID":"KEEP"},
      "reminderIDsMergeableOrdering":{"counter":9,"modificationTime":2,"replicaID":"ORD"},
      "name":{"counter":1,"modificationTime":3}},"version":2}
      """#
    let result = applyMembershipWrite(toTokenMapJSON: existing, coreDataTimestamp: 10, newReplicaID: "NEW")
    #expect(result["version"] == .number(2))
    #expect(result["map"]?["name"] == (try? JSONValue.parse(#"{"counter":1,"modificationTime":3}"#)))
    #expect(
      result["map"]?[membershipTokenField]
        == .object([("counter", .number(5)), ("modificationTime", .number(10)), ("replicaID", .string("KEEP"))]))
    #expect(
      result["map"]?[orderingTokenField]
        == .object([("counter", .number(10)), ("modificationTime", .number(10)), ("replicaID", .string("ORD"))]))
  }

  @Test("does not create an ordering entry when absent")
  func writeNoOrdering() {
    let result = applyMembershipWrite(toTokenMapJSON: #"{"map":{}}"#, coreDataTimestamp: 10, newReplicaID: "NEW")
    #expect(result["map"]?[orderingTokenField] == nil)
  }
}
