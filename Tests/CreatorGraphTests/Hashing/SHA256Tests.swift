import Foundation
import Testing
#if canImport(CryptoKit)
import CryptoKit
#endif
@testable import CreatorGraph

/// `SHA256` (FIPS 180-4), our own so image keys are the same on every platform: the NIST test vectors, and on macOS equality with
/// CryptoKit's output over message lengths that straddle the padding's block boundaries.
struct SHA256Tests {
    /// The NIST byte-oriented vectors (the "abc", two-block and 896-bit messages of FIPS 180-4's examples, and the empty message).
    static let vectors: [(message: String, digest: String)] = [
        ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
         "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
        ("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
         "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"),
    ]

    @Test func theNISTVectorsHold() {
        for (message, digest) in Self.vectors {
            #expect(SHA256.hex(of: Data(message.utf8)) == digest, "\"\(message.prefix(20))…\"")
        }
    }

    @Test func aMillionAsHashToTheNISTLongMessageDigest() {
        let message = Data(repeating: 0x61, count: 1_000_000)
        #expect(SHA256.hex(of: message) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    @Test func aSliceOfDataHashesAsItsOwnBytes() {
        let padded = Data([9, 9, 9]) + Data("abc".utf8)
        let slice = padded.dropFirst(3)
        #expect(slice.startIndex == 3)
        #expect(SHA256.hex(of: slice) == Self.vectors[1].digest)
    }

    @Test func theDigestIsThirtyTwoBytesAndTheHexSixtyFourLowercaseDigits() {
        #expect(SHA256.hash(Data("abc".utf8)).count == 32)
        let hex = SHA256.hex(of: Data("abc".utf8))
        #expect(hex.count == 64 && hex == hex.lowercased())
    }

    #if canImport(CryptoKit)
    /// Bytes from a fixed generator, so a failure reproduces.
    static func message(count: Int) -> Data {
        var state: UInt32 = 2_463_534_242
        return Data((0..<count).map { _ in
            state = state &* 1_664_525 &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: state >> 24)
        })
    }

    @Test(arguments: [0, 1, 3, 55, 56, 57, 63, 64, 65, 119, 120, 121, 127, 128, 129, 1_000, 4_096, 65_537])
    func itAgreesWithCryptoKit(_ length: Int) {
        let data = Self.message(count: length)
        #expect(SHA256.hash(data) == Array(CryptoKit.SHA256.hash(data: data)), "\(length) bytes")
    }
    #endif
}
