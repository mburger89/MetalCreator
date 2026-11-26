import CreatorGeometry
import Foundation

/// A grey picture as a PNG with stored (uncompressed) deflate blocks, so the bytes are fixed on every platform (DR-5 R13).
public enum GreyPNG {
    private static let blockSize = 65_535

    public static func encode(_ pixels: GreyPixels) -> Data {
        var header: [UInt8] = []
        header += bigEndian(UInt32(pixels.width))
        header += bigEndian(UInt32(pixels.height))
        header += [8, 0, 0, 0, 0]  // depth 8, colour type 0 (grey), deflate, adaptive filtering, no interlace

        // Each scanline starts with filter type 0 (none).
        var raw: [UInt8] = []
        raw.reserveCapacity(pixels.height * (pixels.width + 1))
        for row in 0..<pixels.height {
            raw.append(0)
            raw += pixels.bytes[(row * pixels.width)..<((row + 1) * pixels.width)]
        }

        var zlib: [UInt8] = [0x78, 0x01]
        var start = 0
        repeat {
            let end = Swift.min(start + blockSize, raw.count)
            let length = UInt16(end - start)
            zlib.append(end == raw.count ? 1 : 0)
            zlib += [UInt8(length & 0xFF), UInt8(length >> 8), UInt8(~length & 0xFF), UInt8(~length >> 8)]
            zlib += raw[start..<end]
            start = end
        } while start < raw.count
        zlib += bigEndian(adler32(raw))

        var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        out += chunk("IHDR", header)
        out += chunk("IDAT", zlib)
        out += chunk("IEND", [])
        return Data(out)
    }

    private static func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
        let name = Array(type.utf8)
        return bigEndian(UInt32(body.count)) + name + body + bigEndian(CRC32.checksum(name + body))
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var (a, b): (UInt32, UInt32) = (1, 0)
        for byte in bytes {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        return (b << 16) | a
    }
}
