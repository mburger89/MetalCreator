import Foundation
import Testing
#if canImport(CryptoKit)
import CryptoKit
#endif
@testable import CreatorGraph

/// `SHA1` (FIPS 180-4), our own for the name-based UUIDs `NodeID.scoped` makes: the NIST test vectors, and on macOS equality with
/// CryptoKit's `Insecure.SHA1` over message lengths that straddle the padding's block boundaries. `InstanceScopedTests` pins a
/// scoped identity to its literal value on every platform.
struct SHA1Tests {
    static let vectors: [(message: String, digest: String)] = [
        ("", "da39a3ee5e6b4b0d3255bfef95601890afd80709"),
        ("abc", "a9993e364706816aba3e25717850c26c9cd0d89d"),
        ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "84983e441c3bd26ebaae4aa1f95129e5e54670f1"),
    ]

    @Test func theNISTVectorsHold() {
        for (message, digest) in Self.vectors {
            #expect(HashPadding.hex(SHA1.hash(Array(message.utf8))) == digest, "\"\(message.prefix(20))…\"")
        }
    }

    @Test func aMillionAsHashToTheNISTLongMessageDigest() {
        let digest = SHA1.hash([UInt8](repeating: 0x61, count: 1_000_000))
        #expect(HashPadding.hex(digest) == "34aa973cd4c4daa4f61eeb2bdbad27316534016f")
        #expect(digest.count == 20)
    }

    #if canImport(CryptoKit)
    @Test(arguments: [0, 1, 3, 55, 56, 57, 63, 64, 65, 119, 120, 121, 127, 128, 129, 1_000, 4_096, 65_537])
    func itAgreesWithCryptoKit(_ length: Int) {
        let bytes = Array(SHA256Tests.message(count: length))
        #expect(SHA1.hash(bytes) == Array(Insecure.SHA1.hash(data: bytes)), "\(length) bytes")
    }
    #endif
}
