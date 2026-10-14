import CreatorGraph
import Foundation

/// Reads PNG and JPEG bytes into a `GreyImage` (fields spec §5). On macOS ImageIO does the work (`GreyImageDecoder+ImageIO.swift`,
/// the only user of it); off macOS every call throws `ImageProblem.platformUnsupported` until MetalUI's public decode lands (gap XP-G4).
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
        #if canImport(ImageIO)
        try inspectWithImageIO(data)
        #else
        throw .platformUnsupported
        #endif
    }

    /// The grey picture in `data`. Runs off the caller's actor; throws `ImageProblem` for a bad file and
    /// `CancellationError` when the task is cancelled.
    @concurrent
    public static func decode(_ data: Data) async throws -> GreyImage {
        #if canImport(ImageIO)
        try await decode(data, bandBytes: defaultBandBytes)
        #else
        throw ImageProblem.platformUnsupported
        #endif
    }
}
