import Foundation

/// Whether `data` starts like a picture format that MetalUI's `ImageInfo` does not read (it answers `nil` for anything but PNG
/// and JPEG): GIF, BMP, TIFF, WebP and HEIF. It exists only so `GreyImageDecoder.inspect` can tell "a picture type we refuse"
/// (`ImageProblem.unsupportedType`) from "not a picture, or a damaged one" (`.undecodable`); the size, the format and the
/// orientation of a PNG or JPEG all come from `ImageInfo`.
enum OtherPictureSignature {
    static func matches(_ data: Data) -> Bool {
        data.withUnsafeBytes { bytes in
            func starts(_ text: String, at offset: Int = 0) -> Bool {
                let wanted = Array(text.utf8)
                return bytes.count >= offset + wanted.count && bytes[offset..<(offset + wanted.count)].elementsEqual(wanted)
            }
            return starts("GIF87a") || starts("GIF89a") || starts("BM") || starts("II*\0") || starts("MM\0*")
                || (starts("RIFF") && starts("WEBP", at: 8)) || starts("ftyp", at: 4)
        }
    }
}
