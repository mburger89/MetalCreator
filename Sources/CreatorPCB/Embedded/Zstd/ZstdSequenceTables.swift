/// The code tables of sequences (RFC 8878 §3.1.1.3.2.1) and the default distributions (§3.1.1.3.2.2).
enum ZstdSequenceTables {
    static let literalLengthBase = [Int](0..<16) + [
        16, 18, 20, 22, 24, 28, 32, 40, 48, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536,
    ]
    static let literalLengthBits = [Int](repeating: 0, count: 16) + [
        1, 1, 1, 1, 2, 2, 3, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
    ]
    static let matchLengthBase = [Int](3..<35) + [
        35, 37, 39, 41, 43, 47, 51, 59, 67, 83, 99, 131, 259, 515, 1027, 2051, 4099, 8195, 16387, 32771, 65539,
    ]
    static let matchLengthBits = [Int](repeating: 0, count: 32) + [
        1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
    ]

    static let maxLiteralLengthCode = 35
    static let maxMatchLengthCode = 52
    static let maxOffsetCode = 31

    static let literalLengthDefault = [
        4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 1, 1, 1, 1, 1, -1, -1, -1, -1,
    ]
    static let matchLengthDefault = [
        1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1, -1, -1,
    ]
    static let offsetDefault = [1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1]

    // swiftlint:disable:next force_try
    static let predefinedLiteralLengths: ZstdFSETable = try! ZstdFSETable(normalized: literalLengthDefault, accuracyLog: 6)
    // swiftlint:disable:next force_try
    static let predefinedMatchLengths: ZstdFSETable = try! ZstdFSETable(normalized: matchLengthDefault, accuracyLog: 6)
    // swiftlint:disable:next force_try
    static let predefinedOffsets: ZstdFSETable = try! ZstdFSETable(normalized: offsetDefault, accuracyLog: 5)
}
