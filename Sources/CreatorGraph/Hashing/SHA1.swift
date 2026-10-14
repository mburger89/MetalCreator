import Foundation

/// SHA-1 (FIPS 180-4), in plain Swift. Used only to name a UUID (version 5, RFC 4122 §4.3), as `NodeID.scoped` does: a
/// deterministic identity, not a security measure. Pinned by the NIST test vectors and, on macOS, by equality with CryptoKit's
/// `Insecure.SHA1` (`SHA1Tests`).
enum SHA1 {
    /// The 20-byte digest of `bytes`.
    static func hash(_ bytes: [UInt8]) -> [UInt8] {
        bytes.withUnsafeBytes { hash($0) }
    }

    /// The 20-byte digest of `bytes`.
    static func hash(_ bytes: UnsafeRawBufferPointer) -> [UInt8] {
        var state: [UInt32] = [0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476, 0xC3D2_E1F0]
        withUnsafeTemporaryAllocation(of: UInt32.self, capacity: 80) { schedule in
            let whole = bytes.count / HashPadding.blockSize
            for block in 0..<whole {
                compress(&state, UnsafeRawBufferPointer(rebasing: bytes[block * 64..<block * 64 + 64]), schedule)
            }
            let tail = UnsafeRawBufferPointer(rebasing: bytes[(whole * 64)...])
            HashPadding.finalBlocks(tail: tail, totalCount: bytes.count).withUnsafeBytes { padded in
                for block in 0..<padded.count / HashPadding.blockSize {
                    compress(&state, UnsafeRawBufferPointer(rebasing: padded[block * 64..<block * 64 + 64]), schedule)
                }
            }
        }
        return state.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> UInt32(24 - 8 * $0)) } }
    }

    /// Mixes one 64-byte `block` into `state`; `schedule` is 80 words of scratch.
    private static func compress(_ state: inout [UInt32], _ block: UnsafeRawBufferPointer,
                                 _ schedule: UnsafeMutableBufferPointer<UInt32>) {
        for index in 0..<16 {
            schedule[index] = block.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self).bigEndian
        }
        for index in 16..<80 {
            schedule[index] = rotate(schedule[index - 3] ^ schedule[index - 8] ^ schedule[index - 14] ^ schedule[index - 16], 1)
        }
        var (a, b, c, d, e) = (state[0], state[1], state[2], state[3], state[4])
        for index in 0..<80 {
            let mix: UInt32, constant: UInt32
            switch index {
            case 0..<20: (mix, constant) = ((b & c) | (~b & d), 0x5A82_7999)
            case 20..<40: (mix, constant) = (b ^ c ^ d, 0x6ED9_EBA1)
            case 40..<60: (mix, constant) = ((b & c) | (b & d) | (c & d), 0x8F1B_BCDC)
            default: (mix, constant) = (b ^ c ^ d, 0xCA62_C1D6)
            }
            let next = rotate(a, 5) &+ mix &+ e &+ constant &+ schedule[index]
            (e, d, c, b, a) = (d, c, rotate(b, 30), a, next)
        }
        for (index, word) in [a, b, c, d, e].enumerated() {
            state[index] = state[index] &+ word
        }
    }

    private static func rotate(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value << count) | (value >> (32 - count))
    }
}
