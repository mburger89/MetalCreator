/// The padding SHA-1 and SHA-256 share (FIPS 180-4 §5.1.1): a 1 bit, zeros, and the message's length in bits as a
/// big-endian 64-bit number, so the padded message is a whole number of 64-byte blocks.
enum HashPadding {
    /// The 64-byte block size of both hashes.
    static let blockSize = 64

    /// The last one or two blocks of a message of `totalCount` bytes whose bytes after the last whole block are `tail`
    /// (fewer than 64 of them): `tail`, the 0x80 byte, zeros, then the bit length.
    static func finalBlocks(tail: UnsafeRawBufferPointer, totalCount: Int) -> [UInt8] {
        var bytes = [UInt8](tail)
        bytes.append(0x80)
        while bytes.count % blockSize != blockSize - 8 {
            bytes.append(0)
        }
        let bitCount = UInt64(totalCount) &* 8
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8(truncatingIfNeeded: bitCount >> UInt64(shift)))
        }
        return bytes
    }

    /// `bytes` as 64 lowercase hexadecimal digits (or 40, for SHA-1's twenty bytes): two digits a byte.
    static func hex(_ bytes: [UInt8]) -> String {
        let digits = Array("0123456789abcdef")
        return String(bytes.flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 0x0F)]] })
    }
}
