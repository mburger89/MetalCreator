/// CRC-32 (IEEE 802.3, the polynomial every zip reader checks), by table, in pieces.
public enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    /// The running value for `bytes` after `crc` (start from 0).
    public static func update(_ crc: UInt32, _ bytes: some Sequence<UInt8>) -> UInt32 {
        var value = ~crc
        for byte in bytes { value = table[Int((value ^ UInt32(byte)) & 0xFF)] ^ (value >> 8) }
        return ~value
    }

    /// The CRC-32 of `bytes`.
    public static func checksum(_ bytes: some Sequence<UInt8>) -> UInt32 {
        update(0, bytes)
    }
}
