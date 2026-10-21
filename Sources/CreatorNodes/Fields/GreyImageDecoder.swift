import CreatorGraph
import Foundation

/// Reads PNG and JPEG bytes into a `GreyImage` (fields spec §5). On every platform MetalUI's public `DecodedImage` does the decoding
/// (`GreyImageDecoder+MetalUI.swift`, the only file that imports it; MetalUI S2, gap XP-G4); no Apple image framework is used.
///
/// Images are untrusted input. `inspect` reads only the header (MetalUI's `ImageInfo`) and refuses a file over `ImageLimits.maxBytes`, a side
/// over `ImageLimits.maxSide`, any type but PNG and JPEG, and anything whose header makes no sense, all before a pixel is decoded;
/// a PNG must also be whole (`PNGStructure`). `decode` then asks MetalUI for the 8-bit straight-alpha RGBA and converts it to the
/// grey grid in bands, checking for cancellation between bands. Memory for a legal 8,192 × 8,192 picture: the 16 MB file at most,
/// MetalUI's decoded RGBA (256 MB whatever the bit depth) and the 128 MB result, so about 0.4 GB, plus any transient copy inside
/// MetalUI's decode; the orientation is applied while indexing, so no oriented copy is made. MetalUI's decode itself cannot be
/// cancelled, so a cancellation is seen before and after it and between bands.
///
/// Grey is our own conversion, not MetalUI's `.grey` (Rec. 601 with alpha dropped): Rec. 709 luminance (0.2126 R + 0.7152 G +
/// 0.0722 B) of the colour premultiplied by alpha, i.e. composited against black, so a monochrome file comes out as `v * 257`. A
/// 16-bit file is rounded to 8 bits by MetalUI. The EXIF/TIFF orientation tag (1 to 8) is applied: the grid is the picture as
/// Preview shows it, and width and height swap for 5 to 8.
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

    /// How many bytes of the 16-bit grey grid one band converts between cancellation checks.
    static let defaultBandBytes = 32 * 1024 * 1024

    /// The format and size of `data` from its header, checked against the limits, without decoding any pixels.
    public static func inspect(_ data: Data) throws(ImageProblem) -> Info {
        try inspectHeader(data)
    }

    /// The grey picture in `data`. Runs off the caller's actor; throws `ImageProblem` for a bad file and
    /// `CancellationError` when the task is cancelled.
    @concurrent
    public static func decode(_ data: Data) async throws -> GreyImage {
        try await decode(data, bandBytes: defaultBandBytes)
    }
}
