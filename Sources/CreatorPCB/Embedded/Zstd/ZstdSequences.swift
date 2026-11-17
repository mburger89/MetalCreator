/// The sequences section of a compressed block and their execution (RFC 8878 §3.1.1.3.2 and §3.1.1.4).
enum ZstdSequences {
    /// Appends the block's bytes (literals and matches) to `output`; a block holds at most `ZstdLiterals.blockMaximum` of them.
    static func execute(
        _ section: UnsafeBufferPointer<UInt8>, literals: [UInt8], state: inout ZstdFrameState, output: inout ZstdOutput, ceiling: Int
    ) throws {
        let (count, headerSize) = try sequenceCount(section)
        output.reserve(ZstdLiterals.blockMaximum, ceiling: ceiling)
        guard count > 0 else {
            guard headerSize == section.count, literals.count <= output.capacity else { throw ZstdProblem.damaged }
            let end = output.count
            output.bytes.withUnsafeMutableBufferPointer { buffer in
                guard let target = buffer.baseAddress, !literals.isEmpty else { return }
                literals.withUnsafeBufferPointer { source in
                    if let from = source.baseAddress { (target + end).update(from: from, count: literals.count) }
                }
            }
            output.count += literals.count
            return
        }
        guard headerSize < section.count, section[headerSize] & 3 == 0 else { throw ZstdProblem.damaged }
        let modes = section[headerSize]
        var offset = headerSize + 1
        let ll = try readTable(mode: modes >> 6, section, &offset, limits: (9, 35), previous: state.literalLengths,
                               predefined: ZstdSequenceTables.predefinedLiteralLengths)
        let of = try readTable(mode: (modes >> 4) & 3, section, &offset, limits: (8, 31), previous: state.offsets,
                               predefined: ZstdSequenceTables.predefinedOffsets)
        let ml = try readTable(mode: (modes >> 2) & 3, section, &offset, limits: (9, 52), previous: state.matchLengths,
                               predefined: ZstdSequenceTables.predefinedMatchLengths)
        state.literalLengths = ll
        state.offsets = of
        state.matchLengths = ml
        guard let reader = ZstdBackwardBits(UnsafeBufferPointer(rebasing: section[offset...])) else { throw ZstdProblem.damaged }
        var decoder = ZstdSequenceDecoder(tables: (ll, of, ml), reader: reader, repeats: state.repeats)
        output.count += try run(count: count, decoder: &decoder, literals: literals, output: &output)
        state.repeats = decoder.repeats
    }

    private static func run(count: Int, decoder: inout ZstdSequenceDecoder, literals: [UInt8], output: inout ZstdOutput) throws -> Int {
        let start = output.count
        let blockMaximum = min(ZstdLiterals.blockMaximum, output.capacity)
        var local = decoder
        let written = try output.bytes.withUnsafeMutableBufferPointer { buffer -> Int in
            try literals.withUnsafeBufferPointer { source -> Int in
                guard let out = buffer.baseAddress else { throw ZstdProblem.damaged }
                var position = start
                var used = 0
                for index in 0..<count {
                    let sequence = try local.next(isLast: index == count - 1)
                    let size = sequence.literalLength + sequence.matchLength
                    guard used + sequence.literalLength <= source.count, position - start + size <= blockMaximum,
                          sequence.offset <= position + sequence.literalLength else { throw ZstdProblem.damaged }
                    if sequence.literalLength > 0, let base = source.baseAddress {
                        (out + position).update(from: base + used, count: sequence.literalLength)
                    }
                    used += sequence.literalLength
                    position += sequence.literalLength
                    copyMatch(out, position, offset: sequence.offset, length: sequence.matchLength)
                    position += sequence.matchLength
                }
                let tail = source.count - used
                guard position - start + tail <= blockMaximum, local.isFinished else { throw ZstdProblem.damaged }
                if tail > 0, let base = source.baseAddress { (out + position).update(from: base + used, count: tail) }
                return position - start + tail
            }
        }
        decoder = local
        return written
    }

    private static func copyMatch(_ out: UnsafeMutablePointer<UInt8>, _ position: Int, offset: Int, length: Int) {
        if offset >= length {
            UnsafeMutableRawPointer(out + position).copyMemory(from: out + position - offset, byteCount: length)
        } else {
            for index in 0..<length { out[position + index] = out[position + index - offset] }
        }
    }

    private static func sequenceCount(_ section: UnsafeBufferPointer<UInt8>) throws -> (count: Int, size: Int) {
        guard let first = section.first else { throw ZstdProblem.damaged }
        if first == 0 { return (0, 1) }
        if first < 128 { return (Int(first), 1) }
        if first < 255 {
            guard section.count >= 2 else { throw ZstdProblem.damaged }
            return ((Int(first) - 128) << 8 + Int(section[1]), 2)
        }
        guard section.count >= 3 else { throw ZstdProblem.damaged }
        return (Int(section[1]) + Int(section[2]) << 8 + 0x7F00, 3)
    }

    private static func readTable(
        mode: UInt8, _ section: UnsafeBufferPointer<UInt8>, _ offset: inout Int, limits: (accuracy: Int, symbol: Int),
        previous: ZstdFSETable?, predefined: () throws -> ZstdFSETable
    ) throws -> ZstdFSETable {
        switch mode {
        case 0:
            return try predefined()
        case 1:
            guard offset < section.count, Int(section[offset]) <= limits.symbol else { throw ZstdProblem.damaged }
            offset += 1
            return .rle(symbol: section[offset - 1])
        case 2:
            let (table, used) = try ZstdFSETable.read(
                UnsafeBufferPointer(rebasing: section[offset...]), maxAccuracy: limits.accuracy, maxSymbol: limits.symbol)
            offset += used
            return table
        default:
            guard let previous else { throw ZstdProblem.damaged }
            return previous
        }
    }
}
