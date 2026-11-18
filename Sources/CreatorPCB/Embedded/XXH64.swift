/// XXH64, the hash a zstd frame's content checksum is the low 32 bits of.
public enum XXH64 {
    private static let prime1: UInt64 = 11_400_714_785_074_694_791
    private static let prime2: UInt64 = 14_029_467_366_897_019_727
    private static let prime3: UInt64 = 1_609_587_929_392_839_161
    private static let prime4: UInt64 = 9_650_029_242_287_828_579
    private static let prime5: UInt64 = 2_870_177_450_012_600_261

    public static func hash(_ bytes: UnsafeRawBufferPointer, seed: UInt64 = 0) -> UInt64 {
        let count = bytes.count
        var position = 0
        var result: UInt64
        if count >= 32 {
            var lanes: [UInt64] = [seed &+ prime1 &+ prime2, seed &+ prime2, seed, seed &- prime1]
            while position + 32 <= count {
                for lane in 0..<4 {
                    lanes[lane] = round(lanes[lane], read64(bytes, position))
                    position += 8
                }
            }
            result = rotl(lanes[0], 1) &+ rotl(lanes[1], 7) &+ rotl(lanes[2], 12) &+ rotl(lanes[3], 18)
            for lane in lanes { result = (result ^ round(0, lane)) &* prime1 &+ prime4 }
        } else {
            result = seed &+ prime5
        }
        result = result &+ UInt64(count)
        while position + 8 <= count {
            result = rotl(result ^ round(0, read64(bytes, position)), 27) &* prime1 &+ prime4
            position += 8
        }
        if position + 4 <= count {
            result = rotl(result ^ (UInt64(read32(bytes, position)) &* prime1), 23) &* prime2 &+ prime3
            position += 4
        }
        while position < count {
            result = rotl(result ^ (UInt64(bytes[position]) &* prime5), 11) &* prime1
            position += 1
        }
        result ^= result >> 33
        result = result &* prime2
        result ^= result >> 29
        result = result &* prime3
        result ^= result >> 32
        return result
    }

    private static func round(_ accumulator: UInt64, _ input: UInt64) -> UInt64 {
        rotl(accumulator &+ input &* prime2, 31) &* prime1
    }

    private static func rotl(_ value: UInt64, _ bits: UInt64) -> UInt64 {
        value << bits | value >> (64 - bits)
    }

    private static func read64(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> UInt64 {
        UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
    }

    private static func read32(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> UInt32 {
        UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }
}
