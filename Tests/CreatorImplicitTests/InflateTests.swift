import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorGraph
@testable import CreatorImplicit
#if canImport(Compression)
import Compression
#endif

/// Our own inflate (RFC 1951): stored, fixed and dynamic blocks, held to Apple's Compression where there is one and to pinned streams
/// everywhere, and never a trap on a hostile stream.
struct InflateTests {
    static let storedStream: [UInt8] = [0x01, 0x07, 0x00, 0xF8, 0xFF, 0x73, 0x74, 0x6F, 0x72, 0x65, 0x64, 0x21]
    static let fixedStream: [UInt8] = [0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x57, 0xC8, 0x40, 0x27, 0x01]
    static let fixedPlain = Data("hello hello hello hello".utf8)
    func inflate(_ bytes: [UInt8], size: Int, cancelled: @escaping () -> Bool = { false }) throws -> Data {
        try bytes.withUnsafeBytes { raw in
            try Inflate.inflate(raw, size: size, isCancelled: cancelled)
        }
    }

    func error(_ bytes: [UInt8], size: Int) -> InflateError? {
        do {
            _ = try inflate(bytes, size: size)
            return nil
        } catch {
            return error as? InflateError
        }
    }

    /// Bits, least significant first; a Huffman code goes most significant first.
    struct BitWriter {
        var bytes: [UInt8] = []
        var used = 0
        mutating func put(_ value: Int, _ count: Int) {
            for i in 0..<count {
                if used == 0 { bytes.append(0) }
                bytes[bytes.count - 1] |= UInt8((value >> i) & 1) << UInt8(used)
                used = (used + 1) % 8
            }
        }
        mutating func putCode(_ value: Int, _ count: Int) {
            for i in (0..<count).reversed() { put((value >> i) & 1, 1) }
        }
    }

    /// Every valid stream the suite pins, with its plain size and SHA-256.
    static let pinned: [(name: String, stream: [UInt8], size: Int, hash: String)] = [
        ("fixed", fixedStream, fixedPlain.count, "eac13dc78da3f79858440011e4db4107e9301314511e6d0073320b14c535b824"),
        ("zlib dynamic", InflateFixtures.zlibDynamic, InflateFixtures.zlibDynamicPlain.count, InflateFixtures.zlibDynamicHash),
        ("every symbol", InflateFixtures.everySymbol, InflateFixtures.everySymbolSize, InflateFixtures.everySymbolHash),
    ]

    @Test func storedFixedAndDynamicBlocks() throws {
        #expect(try inflate(Self.storedStream, size: 7) == Data("stored!".utf8))
        #expect(try inflate(Self.fixedStream, size: Self.fixedPlain.count) == Self.fixedPlain)
        // They really are dynamic blocks: BTYPE is bits 1 and 2 of the first byte.
        #expect((InflateFixtures.zlibDynamic[0] >> 1) & 3 == 2)
        #expect((InflateFixtures.everySymbol[0] >> 1) & 3 == 2)
        #expect(try inflate(InflateFixtures.zlibDynamic, size: InflateFixtures.zlibDynamicPlain.count)
                == InflateFixtures.zlibDynamicPlain)
        #expect(try inflate([0x03, 0x00], size: 0) == Data())
        #expect(error([0x03, 0x00], size: 1) == .tooShort)
        #expect(error([], size: 0) == .malformed)
    }

    @Test func pinnedStreamsAgreeEverywhere() throws {
        for item in Self.pinned {
            let plain = try inflate(item.stream, size: item.size)
            #expect(SHA256.hex(of: plain) == item.hash, "\(item.name)")
        }
    }

    @Test func bytesAfterTheFinalBlockAreIgnored() throws {
        #expect(try inflate(Self.storedStream + [1, 2, 3], size: 7) == Data("stored!".utf8))
        #expect(try inflate(Self.fixedStream + [0xFF, 0xFF], size: Self.fixedPlain.count) == Self.fixedPlain)
        #expect(try inflate(InflateFixtures.everySymbol + [0, 0, 0], size: InflateFixtures.everySymbolSize).count
                == InflateFixtures.everySymbolSize)
    }

    @Test(arguments: InflateFixtures.hostile)
    func streamsZlibRefusesWeRefuseAndTheRestAgree(_ item: InflateFixtures.Hostile) throws {
        if let expected = item.expected {
            #expect(try inflate(item.stream, size: expected.count) == expected, "\(item.name)")
        } else {
            #expect(error(item.stream, size: 1000) == .malformed, "\(item.name)")
        }
    }

    #if canImport(Compression)
    func compressed(_ data: Data) -> [UInt8] {
        let capacity = data.count + data.count / 100 + 1024
        var out = [UInt8](repeating: 0, count: capacity)
        let count = data.withUnsafeBytes { source in
            compression_encode_buffer(&out, capacity, source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
        return Array(out[0..<count])
    }

    static func randomBytes(_ count: Int, seed: Int) -> [UInt8] {
        var random = SeededRandom(seed: seed)
        return (0..<count).map { _ in UInt8(truncatingIfNeeded: random.next() >> 24) }
    }

    @Test(arguments: [1, 100, 5000, 100_000, 3_000_000])
    func agreesWithCompression(_ size: Int) throws {
        let random = Data(Self.randomBytes(size, seed: size))
        let repetitive = Data((0..<size).map { UInt8(truncatingIfNeeded: ($0 / 7) % 13 + ($0 % 3)) })
        let text = Data((0..<size).map { UInt8(truncatingIfNeeded: 97 + ($0 * $0 >> 3) % 7) })
        for data in [random, repetitive, text] {
            #expect(try inflate(compressed(data), size: size) == data)
        }
    }

    static let lengthBases = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
    ]
    static let distanceBases = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097,
                                6145, 8193, 12289, 16385, 24577,
    ]

    /// Matches of every length symbol's first and last length and every distance symbol's first and last distance, then random ones,
    /// planted in random bytes: Compression finds them (the byte after each copy is random), so far matches of every range are decoded.
    static func farMatchCorpus() -> (data: Data, pairs: [(length: Int, distance: Int)]) {
        var random = SeededRandom(seed: 99)
        var lengths: [Int] = []
        for (i, base) in lengthBases.enumerated() {
            let extraBits = i < 8 || i == 28 ? 0 : (i - 4) / 4
            lengths += i == 28 ? [258] : [base, base + (1 << extraBits) - 1]
        }
        var distances: [Int] = []
        for (i, base) in distanceBases.enumerated() {
            let extraBits = i < 4 ? 0 : (i - 2) / 2
            distances += [base, base + (1 << extraBits) - 1]
        }
        var pairs: [(length: Int, distance: Int)] = (0..<max(lengths.count, distances.count)).map {
            (length: lengths[$0 % lengths.count], distance: distances[$0 % distances.count])
        }
        for _ in 0..<3000 {
            let length = 3 + Int(random.next() % 256)
            pairs.append((length, length + Int(random.next() % UInt64(32768 - length + 1))))
        }
        var bytes = Self.randomBytes(40_000, seed: 98)
        var planted: [(length: Int, distance: Int)] = []
        for pair in pairs where pair.distance <= bytes.count {
            for _ in 0..<pair.length { bytes.append(bytes[bytes.count - pair.distance]) }
            bytes.append(UInt8(truncatingIfNeeded: random.next() >> 24))
            planted.append(pair)
        }
        return (Data(bytes), planted)
    }

    @Test func farMatchesOfEveryRangeAgreeWithCompression() throws {
        let corpus = Self.farMatchCorpus()
        let lengthSymbols = Set(corpus.pairs.map { pair in Self.lengthBases.lastIndex { $0 <= pair.length }! })
        let distanceSymbols = Set(corpus.pairs.map { pair in Self.distanceBases.lastIndex { $0 <= pair.distance }! })
        #expect(lengthSymbols.count == 29 && distanceSymbols.count == 30, "the corpus plants every symbol's range")
        #expect(corpus.pairs.map(\.distance).max()! > 24_577)
        #expect(try inflate(compressed(corpus.data), size: corpus.data.count) == corpus.data)
    }
    #endif

    func fixedBlock(literals: Int, matches: Int) -> [UInt8] {
        var writer = BitWriter()
        writer.put(1, 1)
        writer.put(1, 2)
        for _ in 0..<literals { writer.putCode(0x30 + 0x61, 8) }
        for _ in 0..<matches {
            writer.putCode(0xC5, 8) // symbol 285: length 258
            writer.putCode(0, 5) // distance 1
        }
        writer.putCode(0, 7)
        return writer.bytes
    }

    @Test func aBombStopsAtTheDeclaredSize() {
        let bomb = fixedBlock(literals: 1, matches: 5000)
        #expect(error(bomb, size: 1000) == .tooLong)
        #expect(error(bomb, size: 258 * 5000 + 1) == nil)
        #expect(error(bomb, size: 258 * 5000 + 2) == .tooShort)
        #expect(error(Self.storedStream, size: 3) == .tooLong)
        #expect(error(Self.fixedStream, size: 3) == .tooLong, "a literal past the size")
    }

    @Test func aHugeDeclaredSizeFailsToAllocateWithItsOwnError() {
        #expect(error(Self.storedStream, size: Int.max) == .allocationFailed)
        #expect(error(Self.storedStream, size: -1) == .malformed)
    }

    @Test func aDistanceBeforeTheStartIsMalformed() {
        var writer = BitWriter()
        writer.put(1, 1)
        writer.put(1, 2)
        writer.putCode(1, 7) // length symbol 257 (3)
        writer.putCode(0, 5) // distance 1, with nothing yet written
        writer.putCode(0, 7)
        #expect(error(writer.bytes, size: 3) == .malformed)
    }

    @Test func manyEmptyFixedBlocksAreFast() throws {
        var writer = BitWriter()
        for _ in 0..<200_000 {
            writer.put(0, 1)
            writer.put(1, 2)
            writer.putCode(0, 7)
        }
        writer.put(1, 1)
        writer.put(1, 2)
        writer.putCode(0, 7)
        #expect(try inflate(writer.bytes, size: 0) == Data())
    }

    @Test func stillCancelsInTheMiddleOfAnyBlockKind() {
        // Literals only: one block, so the checks come from the loop, once per megabyte.
        let cases = [(fixedBlock(literals: 2_500_000, matches: 0), 2_500_000), (fixedBlock(literals: 1, matches: 9_690), 1 + 258 * 9_690)]
        for (stream, size) in cases {
            var asked = 0
            #expect(error(stream, size: size) == nil)
            _ = try? inflate(stream, size: size) { asked += 1; return false }
            #expect(asked == 3, "the block's start, then each megabyte")
            asked = 0
            do {
                _ = try inflate(stream, size: size) { asked += 1; return asked == 2 }
                Issue.record("expected a cancellation")
            } catch {
                #expect(error as? InflateError == .cancelled)
                #expect(asked == 2)
            }
        }
    }

    @Test func storedBlocksAskAboutCancellationToo() {
        // Stored blocks of 64 KB, so the output grows past several megabytes.
        var bytes: [UInt8] = []
        let blocks = (3 << 20) / 65_535
        for i in 0..<blocks {
            bytes += [i == blocks - 1 ? 1 : 0, 0xFF, 0xFF, 0x00, 0x00]
            bytes += [UInt8](repeating: 7, count: 65_535)
        }
        var asked = 0
        do {
            _ = try inflate(bytes, size: blocks * 65_535) {
                asked += 1
                return asked > 3
            }
            Issue.record("expected a cancellation")
        } catch {
            #expect(error as? InflateError == .cancelled)
        }
    }

    @Test func anOverSubscribedCodeLengthCodeIsMalformed() {
        var writer = BitWriter()
        writer.put(1, 1)
        writer.put(2, 2)
        writer.put(0, 5)
        writer.put(0, 5)
        writer.put(0, 4) // four code length codes
        for _ in 0..<4 { writer.put(1, 3) } // four codes of length 1: over-subscribed
        writer.put(0, 16)
        #expect(error(writer.bytes, size: 1) == .malformed)
    }

    @Test func aTruncatedStreamIsMalformedNotATrap() {
        for item in Self.pinned + [("stored", Self.storedStream, 7, "")] {
            for cut in 0..<item.stream.count {
                #expect(error(Array(item.stream[0..<cut]), size: item.size + 10) == .malformed, "\(item.name) cut at \(cut)")
            }
        }
    }

    @Test func everyByteFlippedNeverTraps() throws {
        for item in Self.pinned {
            for index in item.stream.indices {
                for mask: UInt8 in [0x01, 0x80, 0xFF, 0x5A] {
                    var damaged = item.stream
                    damaged[index] ^= mask
                    for size in [0, 23, item.size, 100_000] {
                        if let data = try? inflate(damaged, size: size) {
                            #expect(data.count == size)
                        }
                    }
                }
            }
        }
    }
}
