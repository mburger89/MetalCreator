// Test fixture file: the picture bytes the image tests feed the decoder, and the damaged files among them. The pieces that
// need no Apple framework are here; `TestImages+CoreGraphics.swift` (macOS: PNG, JPEG, GIF and TIFF made with ImageIO) and
// `TestImages+Portable.swift` (elsewhere: PNGs from `PNGWriter`) add the rest.
import Foundation

enum TestImages {
    /// The colour `colourRows` paints at (x, y).
    static func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) { ((x * 6 + y * 5) % 256, (y * 9 + x) % 256, (x * 3 + y * 2) % 256) }

    /// The eight signature bytes and an IHDR chunk claiming `width` × `height`, with nothing after it: what a decompression
    /// bomb's header looks like.
    static func pngHeader(claiming width: UInt32, _ height: UInt32) -> Data {
        var chunk = Data("IHDR".utf8)
        for side in [width, height] { chunk.append(contentsOf: [24, 16, 8, 0].map { side >> UInt32($0) }.map { UInt8($0 & 0xFF) }) }
        chunk.append(contentsOf: [8, 0, 0, 0, 0])
        var file = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13])
        file.append(chunk)
        file.append(contentsOf: [24, 16, 8, 0].map { UInt8((PNGWriter.crc32(chunk) >> UInt32($0)) & 0xFF) })
        return file
    }
}
