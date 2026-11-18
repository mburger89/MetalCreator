/// A frame's header (RFC 8878 §3.1.1.1).
struct ZstdFrameHeader {
    static let windowCeiling: UInt64 = 256 << 20

    var contentSize: UInt64?
    /// The largest distance a match may reach back.
    var windowSize: UInt64
    var hasChecksum: Bool
    /// Bytes the header took.
    var size: Int

    /// Reads the header at the start of `bytes` (after the magic number).
    init(_ bytes: UnsafeBufferPointer<UInt8>) throws {
        guard let descriptor = bytes.first, descriptor & 0x08 == 0 else { throw ZstdProblem.damaged }
        let sizeFlag = Int(descriptor >> 6)
        let singleSegment = descriptor & 0x20 != 0
        hasChecksum = descriptor & 0x04 != 0
        var offset = 1
        var window: UInt64?
        if !singleSegment {
            guard offset < bytes.count else { throw ZstdProblem.damaged }
            let byte = UInt64(bytes[offset])
            offset += 1
            let base: UInt64 = 1 << (10 + (byte >> 3))
            window = base + (base >> 3) * (byte & 7)
        }
        offset += try Self.skipDictionaryID(bytes, at: offset, flag: Int(descriptor & 3))
        let sizeBytes = sizeFlag == 0 ? (singleSegment ? 1 : 0) : 1 << sizeFlag
        guard offset + sizeBytes <= bytes.count else { throw ZstdProblem.damaged }
        var content: UInt64?
        if sizeBytes > 0 {
            var value: UInt64 = 0
            for index in 0..<sizeBytes { value |= UInt64(bytes[offset + index]) << UInt64(8 * index) }
            if sizeFlag == 1 { value += 256 }
            content = value
        }
        offset += sizeBytes
        contentSize = content
        if singleSegment { window = content }
        guard let window else { throw ZstdProblem.damaged }
        windowSize = window
        size = offset
    }

    /// A dictionary id of zero means no dictionary; any other is refused.
    private static func skipDictionaryID(_ bytes: UnsafeBufferPointer<UInt8>, at offset: Int, flag: Int) throws -> Int {
        let count = [0, 1, 2, 4][flag]
        guard offset + count <= bytes.count else { throw ZstdProblem.damaged }
        if (0..<count).contains(where: { bytes[offset + $0] != 0 }) { throw ZstdProblem.dictionary }
        return count
    }
}
