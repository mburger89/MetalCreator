import Foundation

/// Why a STEP or IGES file could not be read from disk (NURBS spec, Import Model), in the plain sentences a node's error shows.
/// Problems with the file's contents are the kernel's; these are the file's being there at all.
public enum ModelImportProblem: Error, Equatable, Sendable {
    /// An Import Model node with no file chosen.
    case notChosen
    /// A linked file that is not where the document says.
    case missing(name: String, folder: String)
    /// A linked path that exists but is not a file (a folder, a device, a pipe).
    case notAFile(name: String)
    /// A linked file that exists but could not be read.
    case unreadable(name: String, reason: String)
    /// A file over `ImageResolver.maxModelFileBytes`.
    case tooLarge
    /// An embedded file whose bytes the document does not hold (a damaged file).
    case embeddedMissing

    public var message: String {
        switch self {
        case .notChosen: "Choose a STEP or IGES file."
        case .missing(let name, let folder): "File '\(name)' wasn't found at \(folder). Relink it in the inspector."
        case .notAFile(let name): "File '\(name)' isn't a file."
        case .unreadable(let name, let reason): "File '\(name)' couldn't be read: \(reason)"
        case .tooLarge: "The model file is larger than 256 MB."
        case .embeddedMissing: "The embedded model file is missing from the document."
        }
    }
}
