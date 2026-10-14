// Test fixture file: small pictures for the tests that choose, link and embed pictures through the app. Plain Swift, so they exist
// on every platform: a PNG with its rows in "stored" (uncompressed) deflate blocks, and a GIF header for the refused format.
import Foundation

enum AppTestImages {
    /// A `width` × `height` 8-bit grey PNG of one level (0…255).
    static func png(_ width: Int = 4, _ height: Int = 4, level: Double = 128) -> Data {
        var raw: [UInt8] = []
        for _ in 0..<height {
            raw.append(0)  // filter type 0: the row as it is
            raw.append(contentsOf: [UInt8](repeating: UInt8(level.rounded()), count: width))
        }
        var file = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        file.append(chunk("IHDR", bigEndian(UInt32(width)) + bigEndian(UInt32(height)) + [8, 0, 0, 0, 0]))
        file.append(chunk("IDAT", zlibStored(raw)))
        file.append(chunk("IEND", []))
        return file
    }

    /// The start of a GIF: a picture format the Image Field refuses.
    static func gif() -> Data {
        Data(Array("GIF89a".utf8) + [8, 0, 8, 0, 0, 0, 0x3B])
    }

    private static func chunk(_ type: String, _ bytes: [UInt8]) -> Data {
        var body = Data(type.utf8)
        body.append(contentsOf: bytes)
        var chunk = Data(bigEndian(UInt32(bytes.count)))
        chunk.append(body)
        chunk.append(contentsOf: bigEndian(crc32(body)))
        return chunk
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }

    private static func zlibStored(_ raw: [UInt8]) -> [UInt8] {
        var stream: [UInt8] = [0x78, 0x01]
        var offset = 0
        repeat {
            let count = min(65_535, raw.count - offset)
            stream.append(offset + count == raw.count ? 1 : 0)
            stream.append(contentsOf: [UInt8(count & 0xFF), UInt8(count >> 8), UInt8(~count & 0xFF), UInt8((~count >> 8) & 0xFF)])
            stream.append(contentsOf: raw[offset..<offset + count])
            offset += count
        } while offset < raw.count
        var low: UInt32 = 1, high: UInt32 = 0
        for byte in raw {
            low = (low + UInt32(byte)) % 65_521
            high = (high + low) % 65_521
        }
        stream.append(contentsOf: bigEndian(high << 16 | low))
        return stream
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
    }
}
