#if canImport(Compression)
import Compression
import Testing
@testable import CreatorImplicit

/// The raw deflater's error path: a stream that can't be made throws once, and tearing down the half-built object is safe.
struct RawDeflaterTests {
    @Test func aStreamThatCannotBeMadeThrowsAndTearsDownCleanly() {
        for _ in 0..<50 {
            #expect(throws: ZipError.self) { _ = try RawDeflater(algorithm: compression_algorithm(0xFFFF)) }
        }
    }

    @Test func theDefaultStreamCompressesAndFinishes() throws {
        let deflater = try RawDeflater()
        var produced = 0
        let input = [UInt8](repeating: 7, count: 10_000)
        try input.withUnsafeBytes { try deflater.process($0, finish: true) { produced += $0.count } }
        #expect(produced > 0 && produced < input.count)
    }
}
#endif
