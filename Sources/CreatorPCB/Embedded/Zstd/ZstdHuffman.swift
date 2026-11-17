/// A Huffman decoding table for the literals (RFC 8878 §4.2): `1 << maxBits` entries, each a symbol and its code length.
struct ZstdHuffmanTable {
    static let maximumBits = 11

    let maxBits: Int
    /// Symbol in the low byte, code length above it.
    private let entries: [UInt16]

    /// Weights of every symbol but the last, which the sum of the others implies.
    init(weights listed: [UInt8]) throws {
        guard !listed.isEmpty, listed.count <= 255 else { throw ZstdProblem.damaged }
        var weights = listed
        var sum = 0
        for weight in weights {
            guard weight <= Self.maximumBits else { throw ZstdProblem.damaged }
            if weight > 0 { sum += 1 << (Int(weight) - 1) }
        }
        guard sum > 0 else { throw ZstdProblem.damaged }
        let bits = Int.bitWidth - sum.leadingZeroBitCount
        let rest = (1 << bits) - sum
        guard bits <= Self.maximumBits, rest & (rest - 1) == 0 else { throw ZstdProblem.damaged }
        weights.append(UInt8(Int.bitWidth - rest.leadingZeroBitCount))
        var starts = [Int](repeating: 0, count: bits + 2)
        var next = 0
        for weight in 1...bits {
            starts[weight] = next
            for value in weights where Int(value) == weight { next += 1 << (weight - 1) }
        }
        var table = [UInt16](repeating: 0, count: 1 << bits)
        for (symbol, value) in weights.enumerated() where value > 0 {
            let weight = Int(value)
            let length = 1 << (weight - 1)
            let entry = UInt16(symbol) | UInt16(bits + 1 - weight) << 8
            for index in starts[weight]..<starts[weight] + length { table[index] = entry }
            starts[weight] += length
        }
        maxBits = bits
        entries = table
    }

    /// Reads the table description at the start of `bytes`; gives the table and the bytes it took.
    static func read(_ bytes: UnsafeBufferPointer<UInt8>) throws -> (table: ZstdHuffmanTable, size: Int) {
        guard let header = bytes.first else { throw ZstdProblem.damaged }
        if header >= 128 {
            let count = Int(header) - 127
            let size = 1 + (count + 1) / 2
            guard size <= bytes.count else { throw ZstdProblem.damaged }
            let weights = (0..<count).map { index -> UInt8 in
                let byte = bytes[1 + index / 2]
                return index % 2 == 0 ? byte >> 4 : byte & 15
            }
            return (try ZstdHuffmanTable(weights: weights), size)
        }
        let size = 1 + Int(header)
        guard header > 0, size <= bytes.count else { throw ZstdProblem.damaged }
        let compressed = UnsafeBufferPointer(rebasing: bytes[1..<size])
        return (try ZstdHuffmanTable(weights: try fseWeights(compressed)), size)
    }

    private static func fseWeights(_ bytes: UnsafeBufferPointer<UInt8>) throws -> [UInt8] {
        let (fse, used) = try ZstdFSETable.read(bytes, maxAccuracy: 6, maxSymbol: 12)
        guard let stream = ZstdBackwardBits(UnsafeBufferPointer(rebasing: bytes[used...])) else { throw ZstdProblem.damaged }
        var reader = stream
        let mask = fse.entries.count - 1
        var first = Int(reader.read(fse.accuracyLog))
        var second = Int(reader.read(fse.accuracyLog))
        var weights = [UInt8]()
        while !reader.isOverrun {
            guard weights.count < 255 else { throw ZstdProblem.damaged }
            let entry = fse.entries[first]
            weights.append(entry.symbol)
            first = (Int(entry.baseline) + Int(reader.read(Int(entry.nbBits)))) & mask
            if reader.isOverrun {
                weights.append(fse.entries[second].symbol)
                return weights
            }
            guard weights.count < 255 else { throw ZstdProblem.damaged }
            let other = fse.entries[second]
            weights.append(other.symbol)
            second = (Int(other.baseline) + Int(reader.read(Int(other.nbBits)))) & mask
            if reader.isOverrun {
                weights.append(fse.entries[first].symbol)
                return weights
            }
        }
        throw ZstdProblem.damaged
    }

    /// Decodes exactly `count` symbols of one stream into `output`; the stream must end with the last symbol.
    func decode(_ stream: UnsafeBufferPointer<UInt8>, count: Int, into output: UnsafeMutablePointer<UInt8>) throws {
        guard var reader = ZstdBackwardBits(stream) else { throw ZstdProblem.damaged }
        for index in 0..<count {
            let entry = entries[Int(reader.peek(maxBits))]
            output[index] = UInt8(truncatingIfNeeded: entry)
            reader.consume(Int(entry >> 8))
            guard !reader.isOverrun else { throw ZstdProblem.damaged }
        }
        guard reader.remaining == 0 else { throw ZstdProblem.damaged }
    }
}
