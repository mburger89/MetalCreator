import CoreGraphics
import CreatorGraph
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads PNG and JPEG bytes into a `GreyImage` (fields spec §5). This file is the only user of ImageIO.
///
/// Images are untrusted input. `inspect` reads only the header and refuses a file over `ImageLimits.maxBytes`, a side over
/// `ImageLimits.maxSide`, any type but PNG and JPEG, and anything ImageIO cannot make sense of, all before a pixel is
/// decoded; `decode` then converts in bands of about 32 MB and checks for cancellation between bands. Memory for a legal
/// 8,192 × 8,192 picture: the 128 MB result and one 32 MB band, plus, for a PNG, the whole decoded `CGImage` that `decodeOnce`
/// keeps (ImageIO would otherwise decode it again for every band): about 256 MB for 8-bit RGBA and 512 MB for 16-bit, so a
/// PNG peaks near 0.4 GB (8-bit) to 0.7 GB (16-bit). A JPEG is read band by band and needs no full-size bitmap.
///
/// Grey comes from the picture's own values: a monochrome file is read as it is; colour is converted to sRGB and then to
/// Rec. 709 luminance (0.2126 R + 0.7152 G + 0.0722 B) of the colour premultiplied by alpha, i.e. composited against black.
/// The EXIF/TIFF orientation tag (1 to 8) is applied: the grid is the picture as Preview shows it, and width and height swap for 5 to 8.
public enum GreyImageDecoder {
    /// The file formats that may be used.
    public enum Format: Sendable, Equatable {
        case png, jpeg

        /// The extension a file of this format is saved with.
        public var fileExtension: String { self == .png ? "png" : "jpg" }
    }

    /// What a header says.
    public struct Info: Sendable, Equatable {
        public let width: Int
        public let height: Int
        public let format: Format
    }

    /// How many bytes of 16-bit bitmap one band may take.
    static let defaultBandBytes = 32 * 1024 * 1024

    /// The format and size of `data` from its header, checked against the limits, without decoding any pixels.
    public static func inspect(_ data: Data) throws(ImageProblem) -> Info {
        guard data.count <= ImageLimits.maxBytes else { throw .tooManyBytes(data.count) }
        guard let source = makeSource(data) else { throw .undecodable }
        let info = try header(of: source)
        // ImageIO reads a PNG cut short as a black picture without complaint; a JPEG cut short it reports once decoded.
        guard info.format != .png || PNGStructure.isWhole(data) else { throw .undecodable }
        return info
    }

    /// The grey picture in `data`. Runs off the caller's actor; throws `ImageProblem` for a bad file and
    /// `CancellationError` when the task is cancelled.
    @concurrent
    public static func decode(_ data: Data) async throws -> GreyImage {
        try await decode(data, bandBytes: defaultBandBytes)
    }

    /// `decode(_:)` with the size of a band chosen, so a test can make a small picture take several bands.
    @concurrent
    static func decode(_ data: Data, bandBytes: Int) async throws -> GreyImage {
        try Task.checkCancellation()
        let info = try inspect(data)
        // ImageIO decodes a PNG whole each time a band is drawn from it (16 passes for a large colour picture, measured), so a PNG
        // is decoded once, up front, and the bands are drawn from that; a JPEG is read a band at a time and needs no such copy.
        let decodeOnce = info.format == .png
        let options = [kCGImageSourceShouldCache: decodeOnce, kCGImageSourceShouldCacheImmediately: decodeOnce] as CFDictionary
        // The image from CreateImageAtIndex is unrotated (no kCGImageSourceCreateThumbnailWithTransform), so its size is the
        // header's size swapped back for orientations 5 to 8; greyPixels turns it into the oriented grid band by band.
        guard let source = makeSource(data), let orientation = orientation(of: source),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options),
              image.width == (orientation.swapsSides ? info.height : info.width),
              image.height == (orientation.swapsSides ? info.width : info.height) else { throw ImageProblem.undecodable }
        let pixels = try greyPixels(of: image, orientation: orientation, bandBytes: bandBytes)
        // A cut-short file can still hand back an image; the source knows it was not whole.
        guard CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let grey = GreyImage(width: info.width, height: info.height, pixels: pixels) else { throw ImageProblem.undecodable }
        return grey
    }

    private static func makeSource(_ data: Data) -> CGImageSource? {
        CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
    }

    private static func header(of source: CGImageSource) throws(ImageProblem) -> Info {
        guard let type = CGImageSourceGetType(source) as String? else { throw .undecodable }
        let format: Format
        switch type {
        case UTType.png.identifier: format = .png
        case UTType.jpeg.identifier: format = .jpeg
        default: throw .unsupportedType
        }
        guard CGImageSourceGetCount(source) >= 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let storedWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let storedHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              storedWidth >= 1, storedHeight >= 1 else { throw .undecodable }
        // Sizes (and the limit) are those of the oriented picture; the tag is read from the same properties.
        let swapped = Orientation(properties: properties).swapsSides
        let width = swapped ? storedHeight : storedWidth, height = swapped ? storedWidth : storedHeight
        guard width <= ImageLimits.maxSide, height <= ImageLimits.maxSide else { throw .tooManyPixels(width: width, height: height) }
        return Info(width: width, height: height, format: format)
    }

    /// The EXIF/TIFF orientation tag of the first image; a missing or out-of-range tag is 1 (upright).
    private static func orientation(of source: CGImageSource) -> Orientation? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        return Orientation(properties: properties)
    }

    /// The EXIF/TIFF orientation 1 to 8: how the stored picture must be turned to be shown upright.
    private struct Orientation {
        let rawValue: Int

        init(properties: [CFString: Any]) {
            let tag = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            rawValue = (1...8).contains(tag) ? tag : 1
        }

        /// Whether width and height trade places (the 90-degree turns and the two transposes, 5 to 8).
        var swapsSides: Bool { rawValue >= 5 }

        /// Maps a point of the stored picture to the upright picture, both with y down and in pixel units; `width` and
        /// `height` are the stored picture's.
        func transform(width: CGFloat, height: CGFloat) -> CGAffineTransform {
            switch rawValue {
            case 2: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0)
            case 3: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width, ty: height)
            case 4: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)
            case 5: CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
            case 6: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0)
            case 7: CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: height, ty: width)
            case 8: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: width)
            default: .identity
            }
        }
    }

    /// Whether the picture is monochrome with no alpha, so its values can be read without a colour conversion.
    private static func isPlainGrey(_ image: CGImage) -> Bool {
        let hasAlpha: Bool
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: hasAlpha = false
        default: hasAlpha = true
        }
        return image.colorSpace?.model == .monochrome && !hasAlpha
    }

    /// The upright picture's grey values, row 0 first, converted a band of rows at a time. `image` is as stored; each band of
    /// the upright grid is found in the stored picture by the inverse of the orientation, cropped out, and drawn turned.
    private static func greyPixels(of image: CGImage, orientation: Orientation, bandBytes: Int) throws -> [UInt16] {
        let stored = CGSize(width: image.width, height: image.height)
        let turn = orientation.transform(width: stored.width, height: stored.height)
        let width = orientation.swapsSides ? image.height : image.width
        let height = orientation.swapsSides ? image.width : image.height
        let plain = isPlainGrey(image)
        let components = plain ? 1 : 4
        let space = plain ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)
        let alpha = plain ? CGImageAlphaInfo.none : CGImageAlphaInfo.premultipliedLast
        guard let space else { throw ImageProblem.undecodable }
        let bitmapInfo = alpha.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
        let rowBytes = width * components * MemoryLayout<UInt16>.stride
        let bandRows = max(1, min(height, bandBytes / rowBytes))
        var pixels = [UInt16](repeating: 0, count: width * height)
        var top = 0
        while top < height {
            try Task.checkCancellation()
            let rows = min(bandRows, height - top)
            guard let context = CGContext(data: nil, width: width, height: rows, bitsPerComponent: 16, bytesPerRow: rowBytes,
                                          space: space, bitmapInfo: bitmapInfo),
                  let data = context.data else { throw ImageProblem.undecodable }
            // The band of the upright grid, and the rows and columns of the stored picture it comes from (whole pixels, y down).
            let source = CGRect(x: 0, y: top, width: width, height: rows).applying(turn.inverted()).integral
            guard let band = image.cropping(to: source) else { throw ImageProblem.undecodable }
            // The crop's own space is y up, its top at its height; the context's row 0 is its top. So: flip the crop to y down,
            // put it where it lies in the stored picture, turn it upright, shift the band to the context's top, flip back.
            context.interpolationQuality = .none
            context.concatenate(
                CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: source.height)
                    .concatenating(CGAffineTransform(translationX: source.minX, y: source.minY))
                    .concatenating(turn)
                    .concatenating(CGAffineTransform(translationX: 0, y: -CGFloat(top)))
                    .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(rows))))
            context.draw(band, in: CGRect(origin: .zero, size: source.size))
            let raw = UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt16.self), count: width * rows * components)
            for index in 0..<(width * rows) {
                pixels[top * width + index] = plain
                    ? UInt16(littleEndian: raw[index])
                    : luminance(red: raw[index * 4], green: raw[index * 4 + 1], blue: raw[index * 4 + 2])
            }
            top += rows
        }
        return pixels
    }

    /// Rec. 709 luminance of premultiplied little-endian 16-bit components, rounded.
    private static func luminance(red: UInt16, green: UInt16, blue: UInt16) -> UInt16 {
        let weighted = 2126 * Int(UInt16(littleEndian: red)) + 7152 * Int(UInt16(littleEndian: green))
            + 722 * Int(UInt16(littleEndian: blue))
        return UInt16(min((weighted + 5000) / 10_000, 65_535))
    }
}
