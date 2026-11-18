/// The literals section of a compressed block (RFC 8878 §3.1.1.3.1).
enum ZstdLiterals {
    static let blockMaximum = 128 * 1024

    /// The literals and the bytes of `block` they took. A new Huffman table is kept in `state` for treeless sections.
    static func decode(_ block: UnsafeBufferPointer<UInt8>, state: inout ZstdFrameState) throws -> (literals: [UInt8], size: Int) {
        guard let first = block.first else { throw ZstdProblem.damaged }
        let kind = first & 3
        let format = Int(first >> 2) & 3
        if kind < 2 { return try plain(block, rle: kind == 1, format: format) }
        let headerSize = [3, 3, 4, 5][format]
        let bits = [10, 10, 14, 18][format]
        guard headerSize <= block.count else { throw ZstdProblem.damaged }
        var header = 0
        for index in 0..<headerSize { header |= Int(block[index]) << (8 * index) }
        let regenerated = (header >> 4) & ((1 << bits) - 1)
        let compressed = (header >> (4 + bits)) & ((1 << bits) - 1)
        guard regenerated <= blockMaximum, compressed <= block.count - headerSize else { throw ZstdProblem.damaged }
        let payload = UnsafeBufferPointer(rebasing: block[headerSize..<headerSize + compressed])
        var streams = payload
        if kind == 2 {
            let (table, used) = try ZstdHuffmanTable.read(payload)
            state.huffman = table
            streams = UnsafeBufferPointer(rebasing: payload[used...])
        }
        guard let table = state.huffman else { throw ZstdProblem.damaged }
        var literals = [UInt8](repeating: 0, count: regenerated)
        try literals.withUnsafeMutableBufferPointer { output in
            guard let base = output.baseAddress else { return }
            if format == 0 {
                try table.decode(streams, count: regenerated, into: base)
            } else {
                try decodeFour(table, streams, count: regenerated, into: base)
            }
        }
        return (literals, headerSize + compressed)
    }

    private static func plain(_ block: UnsafeBufferPointer<UInt8>, rle: Bool, format: Int) throws -> (literals: [UInt8], size: Int) {
        let first = Int(block[0])
        let headerSize = format == 1 ? 2 : (format == 3 ? 3 : 1)
        guard headerSize <= block.count else { throw ZstdProblem.damaged }
        var regenerated = first >> 3
        if format == 1 { regenerated = first >> 4 | Int(block[1]) << 4 }
        if format == 3 { regenerated = first >> 4 | Int(block[1]) << 4 | Int(block[2]) << 12 }
        guard regenerated <= blockMaximum else { throw ZstdProblem.damaged }
        if rle {
            guard headerSize < block.count else { throw ZstdProblem.damaged }
            return ([UInt8](repeating: block[headerSize], count: regenerated), headerSize + 1)
        }
        guard regenerated <= block.count - headerSize else { throw ZstdProblem.damaged }
        return (Array(block[headerSize..<headerSize + regenerated]), headerSize + regenerated)
    }

    private static func decodeFour(
        _ table: ZstdHuffmanTable, _ streams: UnsafeBufferPointer<UInt8>, count: Int, into output: UnsafeMutablePointer<UInt8>
    ) throws {
        guard streams.count >= 6 else { throw ZstdProblem.damaged }
        let sizes = (0..<3).map { Int(streams[2 * $0]) | Int(streams[2 * $0 + 1]) << 8 }
        let lengths = sizes + [streams.count - 6 - sizes[0] - sizes[1] - sizes[2]]
        guard lengths[3] > 0 else { throw ZstdProblem.damaged }
        let each = (count + 3) / 4
        var offset = 6
        var produced = 0
        for index in 0..<4 {
            let length = lengths[index]
            let symbols = index < 3 ? each : count - 3 * each
            guard symbols >= 0, length > 0 else { throw ZstdProblem.damaged }
            let stream = UnsafeBufferPointer(rebasing: streams[offset..<offset + length])
            try table.decode(stream, count: symbols, into: output + produced)
            offset += length
            produced += symbols
        }
    }
}
