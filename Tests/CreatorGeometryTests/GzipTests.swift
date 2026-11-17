import Foundation
import Testing
@testable import CreatorGeometry

/// The gzip reader (RFC 1952), over members written here with stored deflate blocks.
struct GzipTests {
    static let payload = Data((0..<70_000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) } + Array("ISO-10303-21;".utf8))

    static func le32(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * UInt32($0))) }
    }

    /// Stored deflate blocks of at most 65,535 bytes each.
    static func stored(_ data: Data) -> [UInt8] {
        var out: [UInt8] = []
        var rest = [UInt8](data)[...]
        repeat {
            let chunk = rest.prefix(65_535)
            rest = rest.dropFirst(chunk.count)
            let length = UInt16(chunk.count)
            out += [rest.isEmpty ? 1 : 0, UInt8(length & 255), UInt8(length >> 8), UInt8(~length & 255), UInt8(~length >> 8)]
            out += chunk
        } while !rest.isEmpty
        return out
    }

    /// One member: header (`flags` and the extra bytes it implies), stored blocks, CRC-32 and ISIZE.
    static func gzip(_ data: Data, flags: UInt8 = 0, header: [UInt8] = [], crc: UInt32? = nil, size: UInt32? = nil) -> Data {
        var out: [UInt8] = [0x1F, 0x8B, 8, flags, 0, 0, 0, 0, 0, 3] + header
        out += stored(data)
        out += le32(crc ?? CRC32.checksum(data)) + le32(size ?? UInt32(truncatingIfNeeded: data.count))
        return Data(out)
    }

    func read(_ data: Data, limit: Int = 1 << 20, cancelled: @escaping () -> Bool = { false }) throws(GzipError) -> Data {
        try Gzip.decompress(data, limit: limit, isCancelled: cancelled)
    }

    @Test func roundTripsStoredBlocks() throws {
        let file = Self.gzip(Self.payload)
        #expect(Gzip.isGzip(file))
        #expect(try read(file) == Self.payload)
    }

    @Test func readsNameAndComment() throws {
        let header = Array("model.step".utf8) + [0] + Array("made here".utf8) + [0]
        #expect(try read(Self.gzip(Self.payload, flags: 8 | 16, header: header)) == Self.payload)
        let extra: [UInt8] = [3, 0, 1, 2, 3]
        #expect(try read(Self.gzip(Self.payload, flags: 4 | 8, header: extra + Array("a".utf8) + [0])) == Self.payload)
    }

    @Test func refusesBadCRC() {
        let file = Self.gzip(Self.payload, crc: CRC32.checksum(Self.payload) ^ 1)
        #expect(throws: GzipError.checksumMismatch) { try read(file) }
    }

    @Test func refusesSizeOverLimit() {
        let file = Self.gzip(Data(repeating: 7, count: 300))
        #expect(throws: GzipError.tooLarge(limit: 200)) { try read(file, limit: 200) }
    }

    @Test func refusesTruncated() {
        let file = Self.gzip(Self.payload)
        #expect(throws: GzipError.malformed) { try read(file.prefix(file.count / 2), limit: .max) }
        #expect(throws: GzipError.malformed) { try read(file.prefix(12), limit: .max) }
    }

    @Test func refusesNotGzip() {
        #expect(throws: GzipError.notGzip) { try read(Data("ISO-10303-21;".utf8)) }
        #expect(!Gzip.isGzip(Data()))
    }

    @Test func refusesSecondMember() {
        let first = Self.gzip(Data("one".utf8))
        let second = Self.gzip(Data("two".utf8))
        #expect(throws: GzipError.malformed) { try read(first + second) }
    }

    @Test func cancels() {
        // Relies on `Inflate` asking `isCancelled` before it reads the first block.
        let file = Self.gzip(Self.payload)
        #expect(throws: GzipError.cancelled) { try read(file, cancelled: { true }) }
    }

    @Test func readsHeaderCRC() throws {
        let fixed: [UInt8] = [0x1F, 0x8B, 8, 2, 0, 0, 0, 0, 0, 3]
        let good = UInt16(truncatingIfNeeded: CRC32.checksum(fixed))
        #expect(try read(Self.gzip(Self.payload, flags: 2, header: [UInt8(good & 255), UInt8(good >> 8)])) == Self.payload)
        let bad = good ^ 1
        #expect(throws: GzipError.malformed) {
            try read(Self.gzip(Self.payload, flags: 2, header: [UInt8(bad & 255), UInt8(bad >> 8)]))
        }
    }

    @Test func refusesHostileHeaders() {
        let tiny = Data("x".utf8)
        #expect(throws: GzipError.malformed) { try read(Self.gzip(tiny, flags: 4, header: [0xFF, 0xFF, 1, 2, 3])) }
        #expect(throws: GzipError.malformed) { try read(Self.gzip(tiny, flags: 8, header: Array("name".utf8))) }
        #expect(throws: GzipError.malformed) { try read(Self.gzip(tiny, flags: 0x20)) }
    }

    @Test func checksTheLimitBeforeInflating() {
        var bytes: [UInt8] = [0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 3]
        bytes += [UInt8](repeating: 0xFF, count: 20) + Self.le32(0) + Self.le32(300)
        #expect(throws: GzipError.tooLarge(limit: 200)) { try read(Data(bytes), limit: 200) }
    }
}
