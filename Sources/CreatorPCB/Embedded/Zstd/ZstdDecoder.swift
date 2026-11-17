import Foundation

/// A portable zstd decoder (RFC 8878): one frame, no dictionaries, bounded input and output.
public enum ZstdDecoder {
    private static let magic: UInt32 = 0xFD2F_B528

    /// One frame (skippable frames before it are skipped; data after the frame is refused).
    /// Throws a `ZstdProblem`, or `CancellationError` when `isCancelled` says so (asked at least once per block of output).
    public static func decode(_ frame: Data, limit: Int, isCancelled: () -> Bool) throws -> Data {
        try frame.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            return try decode(bytes, limit: limit, isCancelled: isCancelled)
        }
    }

    private static func decode(_ bytes: UnsafeBufferPointer<UInt8>, limit requested: Int, isCancelled: () -> Bool) throws -> Data {
        let limit = max(requested, 0)
        var offset = try skipSkippable(bytes)
        guard offset + 4 <= bytes.count, word(bytes, offset) == magic else { throw ZstdProblem.damaged }
        offset += 4
        let header = try ZstdFrameHeader(UnsafeBufferPointer(rebasing: bytes[offset...]))
        offset += header.size
        if let stated = header.contentSize, stated > UInt64(max(limit, 0)) { throw ZstdProblem.larger(than: limit) }
        guard header.windowSize <= ZstdFrameHeader.windowCeiling else { throw ZstdProblem.window }
        let ceiling = header.contentSize.map { Int($0) } ?? limit + ZstdLiterals.blockMaximum
        var output = ZstdOutput()
        var state = ZstdFrameState()
        offset = try readBlocks(bytes, from: offset, into: &output, state: &state, bounds: (limit, ceiling), isCancelled: isCancelled)
        if let stated = header.contentSize, stated != UInt64(output.count) { throw ZstdProblem.damaged }
        if header.hasChecksum {
            guard offset + 4 <= bytes.count else { throw ZstdProblem.damaged }
            let hash = output.bytes.withUnsafeBytes { XXH64.hash(UnsafeRawBufferPointer(rebasing: $0[0..<output.count])) }
            guard word(bytes, offset) == UInt32(truncatingIfNeeded: hash) else { throw ZstdProblem.damaged }
            offset += 4
        }
        guard offset == bytes.count else { throw ZstdProblem.damaged }
        output.bytes.removeLast(output.bytes.count - output.count)
        return Data(output.bytes)
    }

    private static func readBlocks(
        _ bytes: UnsafeBufferPointer<UInt8>, from start: Int, into output: inout ZstdOutput, state: inout ZstdFrameState,
        bounds: (limit: Int, ceiling: Int), isCancelled: () -> Bool
    ) throws -> Int {
        let (limit, ceiling) = bounds
        var offset = start
        var isLast = false
        while !isLast {
            if isCancelled() { throw CancellationError() }
            guard offset + 3 <= bytes.count else { throw ZstdProblem.damaged }
            let header = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16
            offset += 3
            isLast = header & 1 != 0
            let kind = (header >> 1) & 3
            let size = header >> 3
            guard size <= ZstdLiterals.blockMaximum else { throw ZstdProblem.damaged }
            let stored = kind == 1 ? 1 : size
            guard kind != 3, stored <= bytes.count - offset else { throw ZstdProblem.damaged }
            let body = UnsafeBufferPointer(rebasing: bytes[offset..<offset + stored])
            offset += stored
            if kind == 2 {
                try compressed(body, state: &state, output: &output, ceiling: ceiling)
            } else {
                guard size <= limit - output.count else { throw ZstdProblem.larger(than: limit) }
                output.reserve(size, ceiling: ceiling)
                guard size <= output.capacity else { throw ZstdProblem.damaged }
                store(body, rle: kind == 1, size: size, into: &output)
            }
            guard output.count <= limit else { throw ZstdProblem.larger(than: limit) }
        }
        return offset
    }

    private static func store(_ body: UnsafeBufferPointer<UInt8>, rle: Bool, size: Int, into output: inout ZstdOutput) {
        guard size > 0 else { return }
        let end = output.count
        output.bytes.withUnsafeMutableBufferPointer { buffer in
            guard let target = buffer.baseAddress.map({ $0 + end }) else { return }
            if rle {
                target.update(repeating: body[0], count: size)
            } else if let source = body.baseAddress {
                target.update(from: source, count: size)
            }
        }
        output.count += size
    }

    private static func compressed(
        _ body: UnsafeBufferPointer<UInt8>, state: inout ZstdFrameState, output: inout ZstdOutput, ceiling: Int
    ) throws {
        let (literals, used) = try ZstdLiterals.decode(body, state: &state)
        try ZstdSequences.execute(UnsafeBufferPointer(rebasing: body[used...]), literals: literals, state: &state, output: &output,
                                  ceiling: ceiling)
    }

    private static func skipSkippable(_ bytes: UnsafeBufferPointer<UInt8>) throws -> Int {
        var offset = 0
        while offset + 8 <= bytes.count, word(bytes, offset) & 0xFFFF_FFF0 == 0x184D_2A50 {
            let size = Int(word(bytes, offset + 4))
            guard size <= bytes.count - offset - 8 else { throw ZstdProblem.damaged }
            offset += 8 + size
        }
        return offset
    }

    private static func word(_ bytes: UnsafeBufferPointer<UInt8>, _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
}
