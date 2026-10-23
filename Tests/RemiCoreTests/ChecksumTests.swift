// Ported from remi tests/unit/checksum.test.ts.

import Testing

@testable import RemiCore

@Suite("checksum")
struct ChecksumTests {
  @Test("produces a 128-character hex string (SHA-512)")
  func shape() {
    let result = computeMembershipChecksum("test")
    #expect(result.count == 128)
    #expect(result.allSatisfy { "0123456789abcdef".contains($0) })
  }

  @Test("produces consistent output for the same input")
  func consistent() {
    let input = #"{"memberships":[{"memberID":"ABC","groupID":"DEF","modifiedOn":123}]}"#
    #expect(computeMembershipChecksum(input) == computeMembershipChecksum(input))
  }

  @Test("produces different output for different input")
  func differs() {
    #expect(computeMembershipChecksum("input1") != computeMembershipChecksum("input2"))
  }

  @Test("matches known SHA-512 value")
  func knownEmpty() {
    #expect(
      computeMembershipChecksum("")
        == "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"
    )
  }

  // FIPS 180-4 / NIST example vectors, checked against both the platform and the portable implementation.
  static let vectors: [(String, String)] = [
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

  @Test("matches NIST vectors")
  func vectorsMatch() {
    for (input, digest) in Self.vectors {
      #expect(computeMembershipChecksum(input) == digest)
      #expect(hexString(PortableSHA512.hash(Array(input.utf8))) == digest)
    }
  }

  @Test("portable SHA-512 handles block boundaries and multi-byte UTF-8")
  func boundaries() {
    for length in [111, 112, 127, 128, 129, 1000] {
      let input = String(repeating: "a", count: length)
      #expect(hexString(PortableSHA512.hash(Array(input.utf8))) == computeMembershipChecksum(input))
    }
    let unicode = #"{"memberships":[{"memberID":"Ünïcødé 😀"}]}"#
    #expect(hexString(PortableSHA512.hash(Array(unicode.utf8))) == computeMembershipChecksum(unicode))
  }
}
