import CreatorKernel
import Foundation

/// Why a picture could not be used (fields spec §4, §5), in the plain sentences a node's error and the app's alerts show.
/// Images are untrusted input, so every way a file can be wrong has a case here and none of them is a crash.
public enum ImageProblem: Error, Equatable, Sendable {
    /// An Image Field with no picture chosen.
    case notChosen
    /// More bytes than `ImageLimits.maxBytes`.
    case tooManyBytes(Int)
    /// A side beyond `ImageLimits.maxSide`.
    case tooManyPixels(width: Int, height: Int)
    /// A format ImageIO reads that is not PNG or JPEG.
    case unsupportedType
    /// Not an image at all, or one that is damaged or cut short.
    case undecodable
    /// A linked path that exists but is not a file (a folder, a device, a pipe).
    case notAFile(name: String)
    /// A linked file that exists but could not be read.
    case unreadable(name: String, reason: String)
    /// A linked file that is not where the document says.
    case notFound(name: String, folder: String)
    /// An embedded image whose bytes the document does not hold (a damaged file).
    case embeddedMissing
    /// This platform cannot decode pictures yet: only macOS can until MetalUI's public decode lands (gap XP-G4).
    case platformUnsupported

    public var message: String {
        switch self {
        case .notChosen:
            "Image Field needs an image: choose one in the inspector."
        case .tooManyBytes(let bytes):
            "That image file is \(Int64(bytes).formatted(.byteCount(style: .memory).locale(.messages))); "
                + "images are limited to \(Int64(ImageLimits.maxBytes).formatted(.byteCount(style: .memory).locale(.messages)))."
        case .tooManyPixels(let width, let height):
            "That image is \(width.formatted(.number.locale(.messages))) × \(height.formatted(.number.locale(.messages))) px; "
                + "a side can be at most \(ImageLimits.maxSide.formatted(.number.locale(.messages))) px."
        case .unsupportedType:
            "Only PNG and JPEG images can be used."
        case .undecodable:
            "That file isn't a readable PNG or JPEG image, or it is damaged."
        case .notAFile(let name):
            "Image '\(name)' isn't a file."
        case .unreadable(let name, let reason):
            "Image '\(name)' couldn't be read: \(reason)"
        case .notFound(let name, let folder):
            "Image '\(name)' wasn't found at \(folder). Relink it in the inspector."
        case .embeddedMissing:
            "This embedded image's data is missing from the file, or damaged. Choose the image again in the inspector."
        case .platformUnsupported:
            "Images need a newer MetalUI on this platform."
        }
    }
}
