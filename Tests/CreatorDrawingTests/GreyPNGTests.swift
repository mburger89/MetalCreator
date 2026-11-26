import CreatorGeometry
import Foundation
import Testing

@testable import CreatorDrawing
@testable import CreatorGraph

/// The grey PNG the SVG embeds (DR-5 R13): stored deflate blocks, our own CRC and Adler checks.
@Suite("Grey PNG")
struct GreyPNGTests {
    private func hex(_ data: Data) -> String {
        SHA256.hash(data).map { String($0, radix: 16).count == 1 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined()
    }

    private func be32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 << 8 | UInt32(bytes[at + $1]) }
    }

    /// The chunks as (type, body), each CRC checked.
    private func chunks(_ data: Data) throws -> [(type: String, body: [UInt8])] {
        let bytes = [UInt8](data)
        #expect(Array(bytes.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var result: [(String, [UInt8])] = []
        var at = 8
        while at < bytes.count {
            let length = Int(be32(bytes, at))
            let type = Array(bytes[(at + 4)..<(at + 8)])
            let body = Array(bytes[(at + 8)..<(at + 8 + length)])
            #expect(CRC32.checksum(type + body) == be32(bytes, at + 8 + length))
            result.append(((String(bytes: type, encoding: .utf8) ?? ""), body))
            at += 12 + length
        }
        return result
    }

    @Test func aPNGOfFourPixels() throws {
        let pixels = try #require(GreyPixels(key: "k", width: 2, height: 2, bytes: [0, 64, 128, 255]))
        let data = GreyPNG.encode(pixels)
        let parts = try chunks(data)
        #expect(parts.map(\.type) == ["IHDR", "IDAT", "IEND"])
        #expect(parts[0].body == [0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 0, 0], "8 bits, colour type 0")
        let zlib = parts[1].body
        #expect(Array(zlib.prefix(2)) == [0x78, 0x01])
        // One final stored block of 2 rows of (filter 0 + 2 bytes) = 6 bytes.
        #expect(Array(zlib[2..<7]) == [1, 6, 0, 0xF9, 0xFF])
        let raw: [UInt8] = [0, 0, 64, 0, 128, 255]
        #expect(Array(zlib[7..<13]) == raw)
        #expect(be32(zlib, 13) == GreyPNG.adler32(raw))
        #expect(zlib.count == 17)
        #expect(hex(data) == "3bdbb4b0cec1691a9ba1b34aeb24bad931d43c65d618a9f428044cb8df65016e")
        #expect(data == GreyPNG.encode(pixels))
    }

    @Test func aRowLongerThanABlockSplits() throws {
        let bytes = [UInt8](repeating: 7, count: 100 * 700)
        let pixels = try #require(GreyPixels(key: "big", width: 100, height: 700, bytes: bytes))
        let zlib = try #require(try chunks(GreyPNG.encode(pixels)).first { $0.type == "IDAT" }).body
        // raw is 700 * 101 = 70,700 bytes: a first block of 65,535 (not final), then 5,165 (final).
        #expect(zlib[2] == 0 && Array(zlib[3..<5]) == [0xFF, 0xFF])
        let second = 2 + 5 + 65_535
        #expect(zlib[second] == 1)
        #expect(Int(zlib[second + 1]) | Int(zlib[second + 2]) << 8 == 5_165)
        #expect(zlib.count == 2 + 5 + 65_535 + 5 + 5_165 + 4)
    }
}
