/// One state of a finite state entropy table: the symbol, and where the next state comes from.
struct ZstdFSEEntry {
    var baseline: UInt16
    var nbBits: UInt8
    var symbol: UInt8
}

/// A decoding table (RFC 8878 §4.1): `1 << accuracyLog` states.
struct ZstdFSETable {
    let accuracyLog: Int
    let entries: [ZstdFSEEntry]

    /// A table whose every state is one symbol and reads no bits (the RLE mode).
    static func rle(symbol: UInt8) -> ZstdFSETable {
        ZstdFSETable(accuracyLog: 0, entries: [ZstdFSEEntry(baseline: 0, nbBits: 0, symbol: symbol)])
    }

    private init(accuracyLog: Int, entries: [ZstdFSEEntry]) {
        self.accuracyLog = accuracyLog
        self.entries = entries
    }

    /// Builds the table of a normalized distribution (`-1` is a probability below one state).
    init(normalized counts: [Int], accuracyLog: Int) throws {
        guard (1...15).contains(accuracyLog), counts.count <= 256 else { throw ZstdProblem.damaged }
        let size = 1 << accuracyLog
        var total = 0
        for count in counts { total += count < 0 ? 1 : count }
        guard total == size else { throw ZstdProblem.damaged }
        var symbols = [UInt8](repeating: 0, count: size)
        var next = [Int](repeating: 0, count: counts.count)
        var high = size - 1
        for (symbol, count) in counts.enumerated() {
            if count == -1 {
                symbols[high] = UInt8(symbol)
                high -= 1
                next[symbol] = 1
            } else {
                next[symbol] = count
            }
        }
        let step = (size >> 1) + (size >> 3) + 3
        var position = 0
        for (symbol, count) in counts.enumerated() where count > 0 {
            for _ in 0..<count {
                symbols[position] = UInt8(symbol)
                position = (position + step) & (size - 1)
                while position > high { position = (position + step) & (size - 1) }
            }
        }
        guard position == 0 else { throw ZstdProblem.damaged }
        var entries = [ZstdFSEEntry]()
        entries.reserveCapacity(size)
        for state in 0..<size {
            let symbol = Int(symbols[state])
            let nextState = next[symbol]
            next[symbol] += 1
            let bits = accuracyLog - (Int.bitWidth - 1 - nextState.leadingZeroBitCount)
            entries.append(ZstdFSEEntry(baseline: UInt16((nextState << bits) - size), nbBits: UInt8(bits), symbol: UInt8(symbol)))
        }
        self.init(accuracyLog: accuracyLog, entries: entries)
    }

    /// Reads a table description from the start of `bytes`; gives the table and how many bytes the description took.
    static func read(_ bytes: UnsafeBufferPointer<UInt8>, maxAccuracy: Int, maxSymbol: Int) throws -> (table: ZstdFSETable, size: Int) {
        var reader = ZstdForwardBits(bytes)
        let accuracyLog = reader.read(4) + 5
        guard accuracyLog <= maxAccuracy else { throw ZstdProblem.damaged }
        var remaining = (1 << accuracyLog) + 1
        var threshold = 1 << accuracyLog
        var bits = accuracyLog + 1
        var counts = [Int]()
        var previousZero = false
        while remaining > 1, counts.count <= maxSymbol {
            if previousZero {
                let run = try zeroRun(&reader)
                guard counts.count + run <= maxSymbol else { throw ZstdProblem.damaged }
                counts.append(contentsOf: repeatElement(0, count: run))
            }
            let limit = 2 * threshold - 1 - remaining
            var count = reader.peek(bits - 1)
            if count < limit {
                reader.consume(bits - 1)
            } else {
                count = reader.peek(bits)
                if count >= threshold { count -= limit }
                reader.consume(bits)
            }
            count -= 1
            remaining -= count < 0 ? -count : count
            guard remaining >= 1, !reader.isOverrun else { throw ZstdProblem.damaged }
            counts.append(count)
            previousZero = count == 0
            while remaining < threshold {
                bits -= 1
                threshold >>= 1
            }
        }
        guard remaining == 1, !reader.isOverrun else { throw ZstdProblem.damaged }
        return (try ZstdFSETable(normalized: counts, accuracyLog: accuracyLog), reader.consumedBytes)
    }

    /// How many symbols with no probability follow a zero: pieces of two bits, a piece of 3 meaning another follows.
    private static func zeroRun(_ reader: inout ZstdForwardBits) throws -> Int {
        var run = 0
        var piece = 3
        while piece == 3 {
            piece = reader.read(2)
            run += piece
            guard !reader.isOverrun else { throw ZstdProblem.damaged }
        }
        return run
    }
}
