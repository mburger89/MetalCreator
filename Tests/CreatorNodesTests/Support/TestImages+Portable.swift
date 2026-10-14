// Test fixture file: the PNGs the image tests can make without CoreGraphics (every platform but macOS): 8-bit and 16-bit grey,
// RGBA, with an EXIF orientation if asked. JPEG, GIF and TIFF need ImageIO; the tests that use them are macOS-only, and
// `GreyImageDecoderPinnedTests` carries a few JPEGs as bytes.
#if !canImport(CoreGraphics)
import Foundation

extension TestImages {
    /// A `width` × `height` monochrome PNG of `bits` (8 or 16) per pixel; `value(x, y)` is 0…255 or 0…65,535. `orientation`
    /// (1 to 8) is written as the EXIF orientation tag; the pixels are stored as given.
    static func grey(_ width: Int, _ height: Int, bits: Int = 8, orientation: Int? = nil, _ value: (Int, Int) -> Int) -> Data {
        if bits == 16 {
            return PNGWriter.encode(width: width, height: height, color: .grey16, orientation: orientation) { x, y in
                let sample = UInt16(clamping: value(x, y))
                return [UInt8(sample >> 8), UInt8(sample & 0xFF)]
            }
        }
        return PNGWriter.encode(width: width, height: height, color: .grey, orientation: orientation) { x, y in
            [UInt8(clamping: value(x, y))]
        }
    }

    /// One grey (0…255) over the whole picture.
    static func flatGrey(_ width: Int, _ height: Int, _ level: Double, orientation: Int? = nil) -> Data {
        grey(width, height, orientation: orientation) { _, _ in Int(level.rounded()) }
    }

    /// A single sRGB colour (components 0…255) with `alpha` (0…255) over a `width` × `height` PNG.
    static func colour(_ width: Int, _ height: Int, red: Int, green: Int, blue: Int, alpha: Int = 255) -> Data {
        let sample = [red, green, blue, alpha].map { UInt8(clamping: $0) }
        return PNGWriter.encode(width: width, height: height, color: .rgba) { _, _ in sample }
    }

    /// A `width` × `height` PNG whose every row differs from its neighbours and every column does too, opaque; `pixel(_:_:)`
    /// gives the colour of the pixel at (x, y).
    static func colourRows(_ width: Int, _ height: Int, orientation: Int? = nil) -> Data {
        PNGWriter.encode(width: width, height: height, color: .rgba, orientation: orientation) { x, y in
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
