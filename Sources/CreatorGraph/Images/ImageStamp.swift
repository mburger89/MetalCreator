import Foundation

/// What an image reference points at right now, cheap to read and to compare. The evaluator mixes it into a node's cache key
/// at every evaluation (fields spec D11), so a linked file edited on disk makes the node run again and an untouched one does not.
public enum ImageStamp: Hashable, Sendable {
    /// An embedded image: whether the document holds its bytes.
    case embedded(ImageHash, isPresent: Bool)
    /// A linked regular file with its modification date and size.
    case file(path: String, modified: Date, size: Int)
    /// A linked path with nothing at it.
    case missing(path: String)
    /// A linked path that is not a regular file.
    case notAFile(path: String)

    /// Whether what this stamp names is a definite thing (an embedded image the document holds, a regular file with its date
    /// and size), so a picture or a failure to decode it may be remembered under it. A missing path or a non-file is not.
    public var isKeepable: Bool {
        switch self {
        case .embedded(_, isPresent: true), .file: true
        case .embedded, .missing, .notAFile: false
        }
    }
}
