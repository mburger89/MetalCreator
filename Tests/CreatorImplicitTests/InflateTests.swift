import Foundation
import Testing
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
    /// zlib level 9 (raw) of `dynamicPlain`: a dynamic block.
    static let dynamicStream: [UInt8] = [
        0x2B, 0xC9, 0x48, 0x55, 0x28, 0x2C, 0xCD, 0x4C, 0xCE, 0x56, 0x48, 0x2A, 0xCA, 0x2F, 0xCF, 0x53, 0x48, 0xCB, 0xAF, 0x50,
        0xC8, 0x2A, 0xCD, 0x2D, 0x28, 0x56, 0xC8, 0x2F, 0x4B, 0x2D, 0x52, 0x28, 0x01, 0x4A, 0xE7, 0x24, 0x56, 0x55, 0x2A, 0xA4,
        0xE4, 0xA7, 0xEB, 0x81, 0x79, 0xA3, 0x8A, 0x47, 0x15, 0x8F, 0x2A, 0x1E, 0x55, 0x3C, 0xAA, 0x78, 0x54, 0xF1, 0x30, 0x52,
        0xCC, 0xC0, 0xC8, 0xC4, 0xCC, 0xC2, 0xCA, 0xC6, 0xCE, 0xC1, 0xC9, 0xC5, 0xCD, 0xC3, 0xCB, 0xC7, 0x2F, 0x20, 0x28, 0x24,
        0x2C, 0x22, 0x2A, 0x26, 0x2E, 0x21, 0x29, 0x25, 0x2D, 0x23, 0x2B, 0x27, 0xAF, 0xA0, 0xA8, 0xA4, 0xAC, 0xA2, 0xAA, 0xA6,
        0xAE, 0xA1, 0xA9, 0xA5, 0xAD, 0xA3, 0xAB, 0xA7, 0x6F, 0x60, 0x68, 0x64, 0x6C, 0x62, 0x6A, 0x66, 0x6E, 0x61, 0x69, 0x65,
        0x6D, 0x63, 0x6B, 0x67, 0xEF, 0xE0, 0xE8, 0xE4, 0xEC, 0xE2, 0xEA, 0xE6, 0xEE, 0xE1, 0xE9, 0xE5, 0xED, 0xE3, 0xEB, 0xE7,
        0x1F, 0x10, 0x18, 0x14, 0x1C, 0x12, 0x1A, 0x16, 0x1E, 0x11, 0x19, 0x15, 0x1D, 0x13, 0x1B, 0x17, 0x9F, 0x90, 0x98, 0x94,
        0x9C, 0x92, 0x9A, 0x96, 0x9E, 0x91, 0x99, 0x95, 0x9D, 0x93, 0x9B, 0x97, 0x5F, 0x50, 0x58, 0x54, 0x5C, 0x52, 0x5A, 0x56,
        0x5E, 0x51, 0x59, 0x55, 0x5D, 0x53, 0x5B, 0x57, 0xDF, 0xD0, 0xD8, 0xD4, 0xDC, 0xD2, 0xDA, 0xD6, 0xDE, 0xD1, 0xD9, 0xD5,
        0xDD, 0xD3, 0xDB, 0xD7, 0x3F, 0x61, 0xE2, 0xA4, 0xC9, 0x53, 0xA6, 0x4E, 0x9B, 0x3E, 0x63, 0xE6, 0xAC, 0xD9, 0x73, 0xE6,
        0xCE, 0x9B, 0xBF, 0x60, 0xE1, 0xA2, 0xC5, 0x4B, 0x96, 0x2E, 0x5B, 0xBE, 0x62, 0xE5, 0xAA, 0xD5, 0x6B, 0xD6, 0xAE, 0x5B,
        0xBF, 0x61, 0xE3, 0xA6, 0xCD, 0x5B, 0xB6, 0x6E, 0xDB, 0xBE, 0x63, 0xE7, 0xAE, 0xDD, 0x7B, 0xF6, 0xEE, 0xDB, 0x7F, 0xE0,
        0xE0, 0xA1, 0xC3, 0x47, 0x8E, 0x1E, 0x3B, 0x0E, 0x00,
    ]
    static var dynamicPlain: Data {
        Data(String(repeating: "the quick brown fox jumps over the lazy dog. ", count: 40).utf8) + Data(0..<200)
    }

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

    @Test func storedFixedAndDynamicBlocks() throws {
        #expect(try inflate(Self.storedStream, size: 7) == Data("stored!".utf8))
        #expect(try inflate(Self.fixedStream, size: Self.fixedPlain.count) == Self.fixedPlain)
        #expect(try inflate(Self.dynamicStream, size: Self.dynamicPlain.count) == Self.dynamicPlain)
        #expect(try inflate([0x03, 0x00], size: 0) == Data())
        #expect(error([0x03, 0x00], size: 1) == .tooShort)
        #expect(error([], size: 0) == .malformed)
    }

    @Test func pinnedStreamsAgreeEverywhere() throws {
        let fixed = try inflate(Self.fixedStream, size: Self.fixedPlain.count)
        #expect(SHA256.hex(of: fixed) == "eac13dc78da3f79858440011e4db4107e9301314511e6d0073320b14c535b824")
        let dynamic = try inflate(Self.dynamicStream, size: Self.dynamicPlain.count)
        #expect(SHA256.hex(of: dynamic) == "10f212ebd1db6153f779aae5d9502af4e1b5275b4bffc119d6c50ae5186ede9a")
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

    @Test(arguments: [1, 100, 5000, 100_000, 3_000_000])
    func agreesWithCompression(_ size: Int) throws {
        var generator = SystemRandomNumberGenerator()
        let random = Data((0..<size).map { _ in UInt8.random(in: 0...255, using: &generator) })
        let repetitive = Data((0..<size).map { UInt8(truncatingIfNeeded: ($0 / 7) % 13 + ($0 % 3)) })
        let text = Data((0..<size).map { UInt8(truncatingIfNeeded: 97 + ($0 * $0 >> 3) % 7) })
        for data in [random, repetitive, text] {
            #expect(try inflate(compressed(data), size: size) == data)
        }
    }
    #endif

    @Test func aBombStopsAtTheDeclaredSize() {
        // A stored-free run: a fixed block of one literal then a maximal match at distance 1, many times.
        var writer = BitWriter()
        writer.put(1, 1)
        writer.put(1, 2)
        writer.putCode(0x30 + 0x61, 8)
        for _ in 0..<5000 {
            writer.putCode(0xC0 + (285 - 280), 8) // 285 is code 11000101, length 258
            writer.putCode(0, 5) // distance 1
        }
        writer.putCode(0, 7)
        #expect(error(writer.bytes, size: 1000) == .tooLong)
        #expect(error(writer.bytes, size: 258 * 5000 + 1) == nil)
        #expect(error(writer.bytes, size: 258 * 5000 + 2) == .tooShort)
        #expect(error(Self.storedStream, size: 3) == .tooLong)
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

    @Test func badCodeLengthsAreMalformed() {
        var writer = BitWriter()
        writer.put(1, 1)
        writer.put(2, 2)
        writer.put(0, 5)
        writer.put(0, 5)
        writer.put(0, 4) // four code length codes
        for _ in 0..<4 { writer.put(1, 3) } // four codes of length 1: over-subscribed
        writer.put(0, 16)
        #expect(error(writer.bytes, size: 1) == .malformed)
        // A stored block whose length and complement disagree.
        #expect(error([0x01, 0x07, 0x00, 0xF8, 0xFE, 0, 0, 0, 0, 0, 0, 0], size: 7) == .malformed)
        // The reserved block type.
        #expect(error([0x07, 0x00], size: 0) == .malformed)
    }

    @Test func aTruncatedStreamIsMalformedNotATrap() {
        for stream in [Self.storedStream, Self.fixedStream, Self.dynamicStream] {
            for cut in 0..<stream.count {
                let result = error(Array(stream[0..<cut]), size: 10_000)
                #expect(result != nil)
                #expect(result != .tooShort || cut > 0)
            }
        }
        #expect(error(Array(Self.dynamicStream.dropLast()), size: Self.dynamicPlain.count) == .malformed)
    }

    @Test func everyByteFlippedNeverTraps() {
        for stream in [Self.fixedStream, Self.dynamicStream] {
            for index in stream.indices {
                for mask: UInt8 in [0x01, 0x80, 0xFF, 0x5A] {
                    var damaged = stream
                    damaged[index] ^= mask
                    for size in [0, 23, Self.dynamicPlain.count, 100_000] {
                        _ = try? inflate(damaged, size: size)
                    }
                }
            }
        }
    }

    @Test func cancellationIsAskedAboutOnceAMegabyte() {
        let big = Data(count: 3 << 20)
        var asked = 0
        // Stored blocks of 64 KB, so the output grows past several megabytes.
        var bytes: [UInt8] = []
        let blocks = big.count / 65_535
        for i in 0..<blocks {
            bytes += [i == blocks - 1 ? 1 : 0, 0xFF, 0xFF, 0x00, 0x00]
            bytes += [UInt8](repeating: 7, count: 65_535)
        }
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
}
