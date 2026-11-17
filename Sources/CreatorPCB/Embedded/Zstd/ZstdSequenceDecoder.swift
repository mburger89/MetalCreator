/// The three interleaved state machines of a block's sequences and the repeat offsets (RFC 8878 §3.1.1.4 and §3.1.1.5).
struct ZstdSequenceDecoder {
    let literalLengths: ZstdFSETable
    let offsets: ZstdFSETable
    let matchLengths: ZstdFSETable
    private(set) var reader: ZstdBackwardBits
    private(set) var repeats: [Int]
    private var literalState: Int
    private var offsetState: Int
    private var matchState: Int

    init(tables: (ZstdFSETable, ZstdFSETable, ZstdFSETable), reader: ZstdBackwardBits, repeats: [Int]) {
        (literalLengths, offsets, matchLengths) = tables
        self.reader = reader
        self.repeats = repeats
        literalState = Int(self.reader.read(tables.0.accuracyLog))
        offsetState = Int(self.reader.read(tables.1.accuracyLog))
        matchState = Int(self.reader.read(tables.2.accuracyLog))
    }

    /// True when every bit of the stream has been used.
    var isFinished: Bool { reader.remaining == 0 }

    /// The next sequence; the states are advanced unless this is the last one.
    mutating func next(isLast: Bool) throws -> (literalLength: Int, matchLength: Int, offset: Int) {
        let literalEntry = literalLengths.entries[literalState]
        let offsetEntry = offsets.entries[offsetState]
        let matchEntry = matchLengths.entries[matchState]
        let literalCode = Int(literalEntry.symbol)
        let offsetCode = Int(offsetEntry.symbol)
        let matchCode = Int(matchEntry.symbol)
        guard literalCode <= ZstdSequenceTables.maxLiteralLengthCode, matchCode <= ZstdSequenceTables.maxMatchLengthCode,
              offsetCode <= ZstdSequenceTables.maxOffsetCode else { throw ZstdProblem.damaged }
        let offsetValue = (1 << offsetCode) + Int(reader.read(offsetCode))
        let matchLength = ZstdSequenceTables.matchLengthBase[matchCode] + Int(reader.read(ZstdSequenceTables.matchLengthBits[matchCode]))
        let literalLength = ZstdSequenceTables.literalLengthBase[literalCode]
            + Int(reader.read(ZstdSequenceTables.literalLengthBits[literalCode]))
        if !isLast {
            literalState = (Int(literalEntry.baseline) + Int(reader.read(Int(literalEntry.nbBits)))) & (literalLengths.entries.count - 1)
            matchState = (Int(matchEntry.baseline) + Int(reader.read(Int(matchEntry.nbBits)))) & (matchLengths.entries.count - 1)
            offsetState = (Int(offsetEntry.baseline) + Int(reader.read(Int(offsetEntry.nbBits)))) & (offsets.entries.count - 1)
        }
        guard !reader.isOverrun else { throw ZstdProblem.damaged }
        return (literalLength, matchLength, try resolve(offsetValue, literalLength: literalLength))
    }

    private mutating func resolve(_ value: Int, literalLength: Int) throws -> Int {
        if value > 3 {
            repeats = [value - 3, repeats[0], repeats[1]]
            return repeats[0]
        }
        let index = value - 1 + (literalLength == 0 ? 1 : 0)
        switch index {
        case 0:
            return repeats[0]
        case 1:
            repeats = [repeats[1], repeats[0], repeats[2]]
        case 2:
            repeats = [repeats[2], repeats[0], repeats[1]]
        default:
            guard repeats[0] > 1 else { throw ZstdProblem.damaged }
            repeats = [repeats[0] - 1, repeats[0], repeats[1]]
        }
        return repeats[0]
    }
}
