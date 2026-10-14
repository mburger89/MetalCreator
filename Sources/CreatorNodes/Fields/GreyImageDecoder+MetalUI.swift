import CreatorGraph
import Foundation
import MetalUI

/// The decoder on every platform: MetalUI's public `DecodedImage` (vendored stb_image, the same bytes in as out on macOS, Linux
/// and Windows), then our own grey conversion and orientation (fields spec §5, errata 2026-10-14).
extension GreyImageDecoder {
    /// `inspect(_:)`: the limits, then the header.
    static func inspectHeader(_ data: Data) throws(ImageProblem) -> Info {
        guard data.count <= ImageLimits.maxBytes else { throw .tooManyBytes(data.count) }
        guard let header = ImageHeader.read(data) else { throw .undecodable }
        let format: Format
        switch header.kind {
        case .png: format = .png
        case .jpeg: format = .jpeg
        case .other: throw .unsupportedType
        }
        // Sizes (and the limit) are those of the oriented picture.
        let swapped = header.orientation >= 5
        let width = swapped ? header.height : header.width, height = swapped ? header.width : header.height
        guard width <= ImageLimits.maxSide, height <= ImageLimits.maxSide else { throw .tooManyPixels(width: width, height: height) }
        // A PNG cut short in the middle of its data must not be trusted, whatever the decoder makes of it.
        guard format != .png || PNGStructure.isWhole(data) else { throw .undecodable }
        return Info(width: width, height: height, format: format)
    }

    /// `decode(_:)` with the size of a band chosen, so a test can make a small picture take several bands.
    @concurrent
    static func decode(_ data: Data, bandBytes: Int) async throws -> GreyImage {
        try Task.checkCancellation()
        let info = try inspect(data)
        // The one step that cannot be interrupted: MetalUI decodes the whole picture to 8-bit straight-alpha RGBA.
        guard let decoded = DecodedImage(data: data, format: .rgba),
              decoded.orientedSize.width == info.width, decoded.orientedSize.height == info.height,
              let tag = Optional(decoded.orientation.exifValue), (1...8).contains(tag) else { throw ImageProblem.undecodable }
        try Task.checkCancellation()
        let pixels = try greyPixels(of: decoded, tag: tag, bandBytes: bandBytes)
        guard let grey = GreyImage(width: info.width, height: info.height, pixels: pixels) else { throw ImageProblem.undecodable }
        return grey
    }

    /// The upright grid's grey values, row 0 first, converted a band of rows at a time (the cancellation points). `decoded` is as
    /// stored; output pixel (x, y) is the stored pixel at `start(y) + x * step`, so no oriented copy of the RGBA is made.
    private static func greyPixels(of decoded: DecodedImage, tag: Int, bandBytes: Int) throws -> [UInt16] {
        let storedWidth = decoded.width, storedHeight = decoded.height
        let width = decoded.orientedSize.width, height = decoded.orientedSize.height
        let bandRows = max(1, min(height, bandBytes / (width * MemoryLayout<UInt16>.stride)))
        // 2126 * c * 257 and its two siblings for an opaque 8-bit sample c: the weights of the sum in `grey(red:green:blue:alpha:)`.
        let red = (0..<256).map { 2126 * $0 * 257 }, green = (0..<256).map { 7152 * $0 * 257 }, blue = (0..<256).map { 722 * $0 * 257 }
        var pixels = [UInt16](repeating: 0, count: width * height)
        try decoded.pixels.withUnsafeBufferPointer { source in
            try pixels.withUnsafeMutableBufferPointer { grid in
                var top = 0
                while top < height {
                    try Task.checkCancellation()
                    for y in top..<min(top + bandRows, height) {
                        let (start, step) = storedRow(tag: tag, y: y, width: storedWidth, height: storedHeight)
                        var offset = start * 4
                        let advance = step * 4
                        for x in 0..<width {
                            // Opaque pixels (nearly all) take the tables; `grey(red:green:blue:alpha:)` is the same sum for the rest.
                            let alpha = source[offset &+ 3]
                            grid[y &* width &+ x] = alpha == 255
                                ? UInt16(truncatingIfNeeded: min((red[Int(source[offset])] &+ green[Int(source[offset &+ 1])]
                                    &+ blue[Int(source[offset &+ 2])] &+ 5_000) / 10_000, 65_535))
                                : grey(red: source[offset], green: source[offset &+ 1], blue: source[offset &+ 2], alpha: alpha)
                            offset &+= advance
                        }
                    }
                    top += bandRows
                }
            }
        }
        return pixels
    }

    /// Where upright row `y` starts in the stored pixels, and the step from one upright pixel to the next, in pixels: the orientation
    /// tag's definition (EXIF 2.32), for a stored picture `width` × `height`.
    private static func storedRow(tag: Int, y: Int, width: Int, height: Int) -> (start: Int, step: Int) {
        switch tag {
        case 2: (y * width + width - 1, -1)
        case 3: ((height - 1 - y) * width + width - 1, -1)
        case 4: ((height - 1 - y) * width, 1)
        case 5: (y, width)
        case 6: (y + (height - 1) * width, -width)
        case 7: (width - 1 - y + (height - 1) * width, -width)
        case 8: (width - 1 - y, width)
        default: (y * width, 1)
        }
    }

    /// Rec. 709 luminance (0.2126 R + 0.7152 G + 0.0722 B) of the colour premultiplied by its alpha, i.e. composited against
    /// black, on 16-bit values (an 8-bit sample `c` is `c * 257`), rounded. A grey pixel `v` with full alpha gives `v * 257`.
    static func grey(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) -> UInt16 {
        func premultiplied(_ sample: UInt8) -> Int {
            alpha == 255 ? Int(sample) * 257 : (Int(sample) * Int(alpha) * 257 + 127) / 255
        }
        let weighted = 2126 * premultiplied(red) + 7152 * premultiplied(green) + 722 * premultiplied(blue)
        return UInt16(min((weighted + 5000) / 10_000, 65_535))
    }
}
