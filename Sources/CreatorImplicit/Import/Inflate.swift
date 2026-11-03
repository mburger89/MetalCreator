import Foundation

/// Why `Inflate` stopped without the bytes it was asked for.
enum InflateError: Error, Equatable {
    /// The stream is not valid DEFLATE (or ends before its last block does).
    case malformed
    /// The stream holds more than the declared size.
    case tooLong
    /// The declared size could not be allocated.
    case allocationFailed
    /// The stream ended cleanly with fewer bytes than the declared size.
    case tooShort
    /// `isCancelled` answered true.
    case cancelled
}

/// Raw DEFLATE (RFC 1951) in plain Swift, so a 3MF reads the same on every platform. The input is untrusted: output stops at the declared
/// `size` (the output is the one allocation that grows with the input's claims: `size` bytes, plus about 13 KB of tables), every read and copy is bounds-checked, nothing recurses, and no input traps. Bytes after the final block are ignored (a zip entry's CRC protects the output).
enum Inflate {
    /// Cancellation is asked about once per this many bytes of output.
    static let cancellationInterval = 1 << 20

    /// Inflates `input` to exactly `size` bytes. Throws `.tooLong` the moment the stream would write past `size`, `.tooShort` when it ends
    /// under it, `.malformed` for a bad or truncated stream.
    static func inflate(_ input: UnsafeRawBufferPointer, size: Int, isCancelled: () -> Bool) throws(InflateError) -> Data {
        guard size >= 0 else { throw .malformed }
        guard let raw = malloc(max(size, 1)) else { throw .allocationFailed }
        let output = raw.assumingMemoryBound(to: UInt8.self)
        do {
            var state = InflateState(input: input, output: output, size: size)
            try state.run(isCancelled: isCancelled)
        } catch {
            free(raw)
            throw error
        }
        return Data(bytesNoCopy: raw, count: size, deallocator: .free)
    }
}

/// A canonical Huffman code: counts per length, symbols in code order, and a table for codes of `fastBits` bits or fewer.
private struct HuffmanTable {
    static let fastBits = 10
    static let maxSymbols = 288
    static let stride = 16 + maxSymbols + (1 << fastBits)

    let counts: UnsafeMutablePointer<UInt16>
    let symbols: UnsafeMutablePointer<UInt16>
    /// `symbol << 4 | length`, or 0 where the code is longer than `fastBits` (or unused).
    let fast: UnsafeMutablePointer<UInt16>

    init(storage: UnsafeMutablePointer<UInt16>) {
        counts = storage
        symbols = storage + 16
        fast = storage + 16 + Self.maxSymbols
    }

    /// Builds the code of `lengths[0..<n]`. An over-subscribed code is malformed, so is an incomplete one except a lone code of length 1
    /// (and no code at all, which decodes nothing).
    func build(_ lengths: UnsafePointer<UInt8>, _ n: Int) throws(InflateError) {
        for i in 0..<16 { counts[i] = 0 }
        for i in 0..<(1 << Self.fastBits) { fast[i] = 0 }
        for i in 0..<n { counts[Int(lengths[i])] += 1 }
        counts[0] = 0
        var left = 1
        var used = 0
        for len in 1...15 {
            left <<= 1
            left -= Int(counts[len])
            if left < 0 { throw .malformed }
            used += Int(counts[len])
        }
        if left > 0 && !(used == 1 && counts[1] == 1) && used != 0 { throw .malformed }
        assign(lengths, n)
    }

    /// Canonical codes: each length starts after the previous length's codes, doubled.
    private func assign(_ lengths: UnsafePointer<UInt8>, _ n: Int) {
        withUnsafeTemporaryAllocation(of: Int.self, capacity: 32) { scratch in
            assignCodes(lengths, n, next: scratch.baseAddress!, position: scratch.baseAddress! + 16)
        }
    }

    private func assignCodes(_ lengths: UnsafePointer<UInt8>, _ n: Int, next: UnsafeMutablePointer<Int>,
                             position: UnsafeMutablePointer<Int>) {
        next.initialize(repeating: 0, count: 16)
        position.initialize(repeating: 0, count: 16)
        var code = 0
        var index = 0
        for len in 1...15 {
            code = (code + (len > 1 ? Int(counts[len - 1]) : 0)) << 1
            next[len] = code
            position[len] = index
            index += Int(counts[len])
        }
        for symbol in 0..<n {
            let len = Int(lengths[symbol])
            if len == 0 { continue }
            symbols[position[len]] = UInt16(symbol)
            position[len] += 1
            if len <= Self.fastBits {
                var reversed = 0
                var c = next[len]
                for _ in 0..<len {
                    reversed = (reversed << 1) | (c & 1)
                    c >>= 1
                }
                let entry = UInt16(symbol << 4 | len)
                var slot = reversed
                while slot < (1 << Self.fastBits) {
                    fast[slot] = entry
                    slot += 1 << len
                }
            }
            next[len] += 1
        }
    }
}

private let lengthBase: [UInt16] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195,
                                    227, 258,
]
private let lengthExtra: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
private let distanceBase: [UInt16] = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
                                      4097, 6145, 8193, 12289, 16385, 24577,
]
private let distanceExtra: [UInt8] = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
private let codeLengthOrder: [Int] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

private struct InflateState {
    let source: UnsafePointer<UInt8>
    var position = 0
    let end: Int
    var bits: UInt64 = 0
    var bitCount = 0
    let output: UnsafeMutablePointer<UInt8>
    let size: Int
    var produced = 0
    var lastCheck = 0

    init(input: UnsafeRawBufferPointer, output: UnsafeMutablePointer<UInt8>, size: Int) {
        // With no input nothing is ever read, so any valid pointer will do.
        source = input.baseAddress?.assumingMemoryBound(to: UInt8.self) ?? UnsafePointer(output)
        end = input.count
        self.output = output
        self.size = size
    }

    mutating func refill() {
        while bitCount <= 56 && position < end {
            bits |= UInt64(source[position]) << UInt64(bitCount)
            position += 1
            bitCount += 8
        }
    }

    /// Takes `n` (at most 32) bits; the buffer must have been refilled. Running dry is a truncated stream.
    mutating func take(_ n: Int) throws(InflateError) -> Int {
        if bitCount < n { throw .malformed }
        let value = Int(bits & ((1 << UInt64(n)) - 1))
        bits >>= UInt64(n)
        bitCount -= n
        return value
    }

    mutating func decode(_ table: HuffmanTable) throws(InflateError) -> Int {
        let entry = table.fast[Int(bits & UInt64((1 << HuffmanTable.fastBits) - 1))]
        if entry != 0 {
            let len = Int(entry & 15)
            if bitCount < len { throw .malformed }
            bits >>= UInt64(len)
            bitCount -= len
            return Int(entry >> 4)
        }
        var code = 0
        var first = 0
        var index = 0
        var peek = bits
        for len in 1...15 {
            code |= Int(peek & 1)
            peek >>= 1
            let count = Int(table.counts[len])
            if code - count < first {
                if bitCount < len { throw .malformed }
                bits >>= UInt64(len)
                bitCount -= len
                return Int(table.symbols[index + (code - first)])
            }
            index += count
            first += count
            first <<= 1
            code <<= 1
        }
        throw .malformed
    }

    mutating func run(isCancelled: () -> Bool) throws(InflateError) {
        let storage = UnsafeMutablePointer<UInt16>.allocate(capacity: 5 * HuffmanTable.stride)
        storage.initialize(repeating: 0, count: 5 * HuffmanTable.stride)
        let lengths = UnsafeMutablePointer<UInt8>.allocate(capacity: 320)
        lengths.initialize(repeating: 0, count: 320)
        defer {
            storage.deallocate()
            lengths.deallocate()
        }
        let literals = HuffmanTable(storage: storage)
        let distances = HuffmanTable(storage: storage + HuffmanTable.stride)
        let codeLengths = HuffmanTable(storage: storage + 2 * HuffmanTable.stride)
        // The fixed code is built on first use and kept: a stream of many fixed blocks must not rebuild it each time.
        let fixedLiterals = HuffmanTable(storage: storage + 3 * HuffmanTable.stride)
        let fixedDistances = HuffmanTable(storage: storage + 4 * HuffmanTable.stride)
        var fixedBuilt = false
        var isFinal = false
        while !isFinal {
            if isCancelled() { throw .cancelled }
            refill()
            isFinal = try take(1) == 1
            switch try take(2) {
            case 0:
                try stored(isCancelled: isCancelled)
            case 1:
                if !fixedBuilt {
                    try buildFixed(fixedLiterals, fixedDistances, lengths)
                    fixedBuilt = true
                }
                try codes(fixedLiterals, fixedDistances, isCancelled: isCancelled)
            case 2:
                try dynamicTables(literals, distances, codeLengths, lengths)
                try codes(literals, distances, isCancelled: isCancelled)
            default:
                throw .malformed
            }
        }
        if produced < size { throw .tooShort }
    }

    func buildFixed(_ literals: HuffmanTable, _ distances: HuffmanTable, _ lengths: UnsafeMutablePointer<UInt8>) throws(InflateError) {
        for i in 0..<144 { lengths[i] = 8 }
        for i in 144..<256 { lengths[i] = 9 }
        for i in 256..<280 { lengths[i] = 7 }
        for i in 280..<288 { lengths[i] = 8 }
        try literals.build(lengths, 288)
        for i in 0..<32 { lengths[i] = 5 }
        try distances.build(lengths, 32)
    }

    mutating func stored(isCancelled: () -> Bool) throws(InflateError) {
        // Drop to a byte boundary, then hand the whole bytes still in the buffer back to the input.
        bits >>= UInt64(bitCount & 7)
        bitCount -= bitCount & 7
        refill()
        let length = try take(16)
        let complement = try take(16)
        if length != (~complement & 0xFFFF) { throw .malformed }
        position -= bitCount / 8
        bits = 0
        bitCount = 0
        if length > end - position { throw .malformed }
        if length > size - produced { throw .tooLong }
        var copied = 0
        while copied < length {
            let piece = min(length - copied, Inflate.cancellationInterval)
            (output + produced).update(from: source + position, count: piece)
            position += piece
            produced += piece
            copied += piece
            try checkCancellation(isCancelled)
        }
    }

    mutating func checkCancellation(_ isCancelled: () -> Bool) throws(InflateError) {
        if produced - lastCheck >= Inflate.cancellationInterval {
            lastCheck = produced
            if isCancelled() { throw .cancelled }
        }
    }

    /// Reads the run-length coded code lengths of both tables, `total` of them, into `lengths`.
    mutating func readLengths(_ codeLengths: HuffmanTable, _ lengths: UnsafeMutablePointer<UInt8>, total: Int) throws(InflateError) {
        var index = 0
        while index < total {
            refill()
            let symbol = try decode(codeLengths)
            if symbol < 16 {
                lengths[index] = UInt8(symbol)
                index += 1
                continue
            }
            var value: UInt8 = 0
            var repeats = 0
            switch symbol {
            case 16:
                if index == 0 { throw .malformed }
                value = lengths[index - 1]
                repeats = 3 + (try take(2))
            case 17:
                repeats = 3 + (try take(3))
            default:
                repeats = 11 + (try take(7))
            }
            if index + repeats > total { throw .malformed }
            for _ in 0..<repeats {
                lengths[index] = value
                index += 1
            }
        }
    }

    mutating func dynamicTables(_ literals: HuffmanTable, _ distances: HuffmanTable, _ codeLengths: HuffmanTable,
                                _ lengths: UnsafeMutablePointer<UInt8>) throws(InflateError) {
        refill()
        let literalCount = try take(5) + 257
        let distanceCount = try take(5) + 1
        let codeLengthCount = try take(4) + 4
        if literalCount > 286 || distanceCount > 30 { throw .malformed }
        for i in 0..<19 { lengths[i] = 0 }
        for i in 0..<codeLengthCount {
            refill()
            lengths[codeLengthOrder[i]] = UInt8(try take(3))
        }
        try codeLengths.build(lengths, 19)
        try readLengths(codeLengths, lengths, total: literalCount + distanceCount)
        if lengths[256] == 0 { throw .malformed }
        try literals.build(lengths, literalCount)
        try distances.build(lengths + literalCount, distanceCount)
    }

    mutating func codes(_ literals: HuffmanTable, _ distances: HuffmanTable, isCancelled: () -> Bool) throws(InflateError) {
        while true {
            // 15 + 5 + 15 + 13 bits is the most one symbol takes, under the 57 or more a refill leaves.
            refill()
            try checkCancellation(isCancelled)
            let symbol = try decode(literals)
            if symbol < 256 {
                if produced >= size { throw .tooLong }
                output[produced] = UInt8(truncatingIfNeeded: symbol)
                produced += 1
                continue
            }
            if symbol == 256 { return }
            try match(symbol, distances)
        }
    }

    /// Copies the match a length symbol starts: its extra bits, then a distance.
    mutating func match(_ symbol: Int, _ distances: HuffmanTable) throws(InflateError) {
        let lengthIndex = symbol - 257
        if lengthIndex >= 29 { throw .malformed }
        let length = Int(lengthBase[lengthIndex]) + (try take(Int(lengthExtra[lengthIndex])))
        let distanceSymbol = try decode(distances)
        if distanceSymbol >= 30 { throw .malformed }
        let distance = Int(distanceBase[distanceSymbol]) + (try take(Int(distanceExtra[distanceSymbol])))
        if distance > produced { throw .malformed }
        if length > size - produced { throw .tooLong }
        let from = output + (produced - distance)
        let to = output + produced
        if distance >= length {
            to.update(from: from, count: length)
        } else {
            for i in 0..<length { to[i] = from[i] }
        }
        produced += length
    }
}
