// Test fixture file: the PNGs the image tests can make without CoreGraphics (every platform but macOS). JPEG, GIF, TIFF, 16-bit
// and rotated pictures need ImageIO, and the tests that use them are macOS-only.
#if !canImport(CoreGraphics)
import Foundation

extension TestImages {
    /// A `width` × `height` monochrome PNG; `value(x, y)` is 0…255.
    static func grey(_ width: Int, _ height: Int, _ value: (Int, Int) -> Int) -> Data {
        PNGWriter.encode(width: width, height: height, color: .grey) { x, y in [UInt8(clamping: value(x, y))] }
    }

    /// One grey (0…255) over the whole picture.
    static func flatGrey(_ width: Int, _ height: Int, _ level: Double) -> Data {
        grey(width, height) { _, _ in Int(level.rounded()) }
    }

    /// A single sRGB colour (components 0…255) with `alpha` (0…255) over a `width` × `height` PNG.
    static func colour(_ width: Int, _ height: Int, red: Int, green: Int, blue: Int, alpha: Int = 255) -> Data {
        let sample = [red, green, blue, alpha].map { UInt8(clamping: $0) }
        return PNGWriter.encode(width: width, height: height, color: .rgba) { _, _ in sample }
    }

    /// A `width` × `height` PNG whose every row differs from its neighbours and every column does too, opaque; `pixel(_:_:)`
    /// gives the colour of the pixel at (x, y).
    static func colourRows(_ width: Int, _ height: Int) -> Data {
        PNGWriter.encode(width: width, height: height, color: .rgba) { x, y in
            let (red, green, blue) = pixel(x, y)
            return [UInt8(red), UInt8(green), UInt8(blue), 255]
        }
    }

    /// A picture whose pixels look like noise, so its PNG does not shrink to a few bytes and can be cut or damaged mid-stream.
    static func noisy(_ size: Int) -> Data {
        var state: UInt32 = 12_345
        return grey(size, size) { _, _ in
            state = state &* 1_664_525 &+ 1_013_904_223
            return Int(state >> 24)
        }
    }
}
#endif
