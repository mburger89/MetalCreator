/// A bitstream read from its end towards its start (RFC 8878 §4.1): the last byte holds a marker bit above
/// the first bit to read. Reading past the start yields zeros and leaves `remaining` negative.
struct ZstdBackwardBits {
    private let bytes: UnsafeBufferPointer<UInt8>
    private(set) var remaining: Int

    /// `nil` when the stream is empty or its last byte has no marker bit.
    init?(_ bytes: UnsafeBufferPointer<UInt8>) {
        guard let last = bytes.last, last != 0 else { return nil }
        self.bytes = bytes
        remaining = (bytes.count - 1) * 8 + (7 - last.leadingZeroBitCount)
    }

    var isOverrun: Bool { remaining < 0 }

    /// The next `count` bits (at most 56) without consuming them; the first bit is the most significant.
    func peek(_ count: Int) -> UInt64 {
        if count == 0 { return 0 }
        if remaining >= count { return bits(at: remaining - count, count: count) }
        let have = max(remaining, 0)
        return have > 0 ? bits(at: 0, count: have) << UInt64(count - have) : 0
    }

    mutating func consume(_ count: Int) { remaining -= count }

    mutating func read(_ count: Int) -> UInt64 {
        let value = peek(count)
        remaining -= count
        return value
    }

    private func bits(at position: Int, count: Int) -> UInt64 {
        let byte = position >> 3
        var word: UInt64 = 0
        if byte + 8 <= bytes.count {
            word = UInt64(littleEndian: UnsafeRawBufferPointer(bytes).loadUnaligned(fromByteOffset: byte, as: UInt64.self))
        } else {
            var index = 0
            while byte + index < bytes.count, index < 8 {
                word |= UInt64(bytes[byte + index]) << UInt64(8 * index)
                index += 1
            }
        }
        return (word >> UInt64(position & 7)) & ((1 << UInt64(count)) - 1)
    }
}

/// A bitstream read from its start, least significant bit first (the FSE table descriptions).
struct ZstdForwardBits {
    private let bytes: UnsafeBufferPointer<UInt8>
    private(set) var position = 0

    init(_ bytes: UnsafeBufferPointer<UInt8>) { self.bytes = bytes }

    /// The bytes touched so far; more than the buffer holds means the description ran off its end.
    var consumedBytes: Int { (position + 7) / 8 }
    var isOverrun: Bool { consumedBytes > bytes.count }

    /// The next `count` bits (at most 16) without consuming them.
    func peek(_ count: Int) -> Int {
        var word = 0
        let first = position >> 3
        for index in 0..<4 where first + index < bytes.count { word |= Int(bytes[first + index]) << (8 * index) }
        return (word >> (position & 7)) & ((1 << count) - 1)
    }

    mutating func consume(_ count: Int) { position += count }

    mutating func read(_ count: Int) -> Int {
        let value = peek(count)
        position += count
        return value
    }
}
