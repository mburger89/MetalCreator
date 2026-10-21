// Test fixture file: a PNG encoder in plain Swift, so the image tests can make pictures where CoreGraphics does not exist.
import Foundation

/// Writes 8-bit (and 16-bit grey) PNGs with no compression: the pixel rows go into "stored" deflate blocks. The files are larger
/// than ImageIO's but valid, which is all a fixture needs (`PNGWriterTests` decodes them with MetalUI's decoder and checks their
/// chunks). An EXIF orientation goes in as an `eXIf` chunk before the data, where MetalUI's `ImageInfo` and decoder read it.
enum PNGWriter {
    /// The PNG colour types this writer makes.
    enum ColorType: UInt8 {
        case grey = 0
        case rgba = 6
        /// Monochrome at 16 bits per sample (big-endian, two bytes per pixel).
        case grey16 = 100

        /// The PNG colour type byte.
        var pngType: UInt8 { self == .rgba ? 6 : 0 }

        /// The bits in a sample.
        var bitDepth: UInt8 { self == .grey16 ? 16 : 8 }

        /// Bytes per pixel.
        var bytesPerPixel: Int {
            switch self {
            case .grey: 1
            case .grey16: 2
            case .rgba: 4
            }
        }
    }

    /// A `width` × `height` picture of `color`; `pixel(x, y)` gives its bytes (one for grey, two for 16-bit grey, four for RGBA).
    /// `orientation` (1 to 8) is written as the EXIF orientation tag; the pixels are stored as given.
    static func encode(width: Int, height: Int, color: ColorType, orientation: Int? = nil,
                       pixel: (Int, Int) -> [UInt8]) -> Data {
        var raw: [UInt8] = []
        raw.reserveCapacity(height * (1 + width * color.bytesPerPixel))
        for y in 0..<height {
            raw.append(0)  // Filter type 0: the row as it is.
            for x in 0..<width {
                raw.append(contentsOf: pixel(x, y))
            }
        }
        var header: [UInt8] = []
        for side in [UInt32(width), UInt32(height)] {
            header.append(contentsOf: bigEndian(side))
        }
        header.append(contentsOf: [color.bitDepth, color.pngType, 0, 0, 0])
        var file = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        file.append(chunk("IHDR", header))
        if let orientation {
            // A big-endian TIFF block with one IFD0 entry: tag 0x0112, type SHORT, count 1, the value.
            let tiff: [UInt8] = [0x4D, 0x4D, 0, 42, 0, 0, 0, 8, 0, 1, 0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, UInt8(orientation), 0, 0, 0, 0, 0, 0]
            file.append(chunk("eXIf", tiff))
        }
        file.append(chunk("IDAT", zlibStored(raw)))
        file.append(chunk("IEND", []))
        return file
    }

    /// The CRC-32 of `data` that ends every PNG chunk.
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }

    /// One chunk: its length, its four-letter type, its bytes and the CRC of type and bytes.
    static func chunk(_ type: String, _ bytes: [UInt8]) -> Data {
        var body = Data(type.utf8)
        body.append(contentsOf: bytes)
        var chunk = Data(bigEndian(UInt32(bytes.count)))
        chunk.append(body)
        chunk.append(contentsOf: bigEndian(crc32(body)))
        return chunk
    }

    /// `raw` as a zlib stream of stored blocks of at most 65,535 bytes, closed by the Adler-32 of `raw`.
    private static func zlibStored(_ raw: [UInt8]) -> [UInt8] {
        var stream: [UInt8] = [0x78, 0x01]
        var offset = 0
        repeat {
            let count = min(65_535, raw.count - offset)
            let isLast = offset + count == raw.count
            stream.append(isLast ? 1 : 0)
            stream.append(contentsOf: [UInt8(count & 0xFF), UInt8(count >> 8), UInt8(~count & 0xFF), UInt8((~count >> 8) & 0xFF)])
            stream.append(contentsOf: raw[offset..<offset + count])
            offset += count
        } while offset < raw.count
        stream.append(contentsOf: bigEndian(adler32(raw)))
        return stream
    }

    private static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var low: UInt32 = 1, high: UInt32 = 0
        for byte in bytes {
            low = (low + UInt32(byte)) % 65_521
            high = (high + low) % 65_521
        }
        return high << 16 | low
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
    }
}
