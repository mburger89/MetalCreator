/// What one frame carries from block to block: the literals' Huffman table, the three sequence tables and the repeat offsets.
struct ZstdFrameState {
    var huffman: ZstdHuffmanTable?
    var literalLengths: ZstdFSETable?
    var offsets: ZstdFSETable?
    var matchLengths: ZstdFSETable?
    var repeats = [1, 4, 8]
}

/// The decoded bytes of a frame. The buffer grows by doubling and holds `count` valid bytes.
struct ZstdOutput {
    var bytes: [UInt8] = []
    var count = 0

    /// Makes room for up to `extra` more bytes without growing past `ceiling` (the buffer may hold less than asked).
    mutating func reserve(_ extra: Int, ceiling: Int) {
        let needed = count + min(extra, max(ceiling - count, 0))
        guard bytes.count < needed else { return }
        let target = min(max(needed, bytes.count * 2, 1 << 16), max(needed, ceiling))
        var grown = [UInt8](repeating: 0, count: target)
        grown.withUnsafeMutableBufferPointer { destination in
            bytes.withUnsafeBufferPointer { source in
                if count > 0, let from = source.baseAddress, let to = destination.baseAddress { to.update(from: from, count: count) }
            }
        }
        bytes = grown
    }

    /// The bytes after the valid ones that the buffer can still take.
    var capacity: Int { bytes.count - count }
}
