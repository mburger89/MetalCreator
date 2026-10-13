// Test fixture file: PNG, JPEG, GIF and TIFF bytes made with ImageIO, and the damaged files the image tests feed the decoder.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TestImages {
    /// A `width` × `height` monochrome picture of `bits` (8 or 16) per pixel; `value(x, y)` is 0…255 or 0…65,535.
    static func grey(_ width: Int, _ height: Int, bits: Int = 8, type: UTType = .png, orientation: Int? = nil,
                     _ value: (Int, Int) -> Int) -> Data {
        let order = bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: bits,
                                      bytesPerRow: width * bits / 8, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue | order),
              let memory = context.data else { return Data() }
        if bits == 16 {
            let pixels = memory.bindMemory(to: UInt16.self, capacity: width * height)
            for y in 0..<height { for x in 0..<width { pixels[y * width + x] = UInt16(littleEndian: UInt16(value(x, y))) } }
        } else {
            let pixels = memory.bindMemory(to: UInt8.self, capacity: width * height)
            for y in 0..<height { for x in 0..<width { pixels[y * width + x] = UInt8(value(x, y)) } }
        }
        return encode(context.makeImage(), as: type, orientation: orientation)
    }

    /// One grey (0…255) over the whole picture, painted with a fill, not pixel by pixel, so a large picture is cheap.
    static func flatGrey(_ width: Int, _ height: Int, _ level: Double, type: UTType = .png, orientation: Int? = nil) -> Data {
        let space = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return Data() }
        context.setFillColor(gray: level / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return encode(context.makeImage(), as: type, orientation: orientation)
    }

    /// A single sRGB colour (components 0…255) with `alpha` (0…255) over a `width` × `height` PNG.
    static func colour(_ width: Int, _ height: Int, red: Int, green: Int, blue: Int, alpha: Int = 255) -> Data {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Data() }
        context.setFillColor(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, alpha: Double(alpha) / 255)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return encode(context.makeImage(), as: .png)
    }

    /// A `width` × `height` sRGB PNG whose every row differs from its neighbours and whose every column does too, opaque; `pixel(_:_:)`
    /// gives the 8-bit colour of the pixel at (x, y), so a test can say what any row must decode to.
    static func colourRows(_ width: Int, _ height: Int, orientation: Int? = nil) -> Data {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let memory = context.data else { return Data() }
        let bytes = memory.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (red, green, blue) = pixel(x, y)
                let offset = (y * width + x) * 4
                (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3]) = (UInt8(red), UInt8(green), UInt8(blue), 255)
            }
        }
        return encode(context.makeImage(), as: .png, orientation: orientation)
    }

    /// The colour `colourRows` paints at (x, y).
    static func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) { ((x * 6 + y * 5) % 256, (y * 9 + x) % 256, (x * 3 + y * 2) % 256) }

    /// A picture whose pixels look like noise, so its PNG does not shrink to a few bytes and can be cut or damaged mid-stream.
    static func noisy(_ size: Int, type: UTType = .png) -> Data {
        var state: UInt32 = 12_345
        return grey(size, size, type: type) { _, _ in
            state = state &* 1_664_525 &+ 1_013_904_223
            return Int(state >> 24)
        }
    }

    /// `orientation` (1 to 8) is written as the EXIF/TIFF orientation tag; the pixels are stored as given.
    static func encode(_ image: CGImage?, as type: UTType, orientation: Int? = nil) -> Data {
        guard let image else { return Data() }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return Data() }
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 1.0]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// The eight signature bytes and an IHDR chunk claiming `width` × `height`, with nothing after it: what a decompression
    /// bomb's header looks like.
    static func pngHeader(claiming width: UInt32, _ height: UInt32) -> Data {
        var chunk = Data("IHDR".utf8)
        for side in [width, height] { chunk.append(contentsOf: [24, 16, 8, 0].map { side >> UInt32($0) }.map { UInt8($0 & 0xFF) }) }
        chunk.append(contentsOf: [8, 0, 0, 0, 0])
        var file = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13])
        file.append(chunk)
        file.append(contentsOf: [24, 16, 8, 0].map { UInt8((crc32(chunk) >> UInt32($0)) & 0xFF) })
        return file
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}
