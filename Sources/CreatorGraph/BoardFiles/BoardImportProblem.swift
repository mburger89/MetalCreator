import Foundation

/// Why a KiCad board file could not be read from disk (KiCad import spec, File setting), in the plain sentences a node's
/// error shows. Problems with the file's contents are `CreatorPCB`'s; these are the file's being there at all.
public enum BoardImportProblem: Error, Equatable, Sendable {
    /// An Import KiCad Board node with no file chosen (or an embedded reference: a board is linked only).
    case notChosen
    /// A linked file that is not where the document says.
    case missing(name: String, folder: String)
    /// A linked path that exists but is not a file (a folder, a device, a pipe).
    case notAFile(name: String)
    /// A linked file that exists but could not be read.
    case unreadable(name: String, reason: String)
    /// A linked file over `ImageResolver.maxBoardFileBytes`.
    case tooLarge

    public var message: String {
        switch self {
        case .notChosen: "Choose a KiCad board file."
        case .missing(let name, let folder): "File '\(name)' wasn't found at \(folder). Relink it in the inspector."
        case .notAFile(let name): "File '\(name)' isn't a file."
        case .unreadable(let name, let reason): "File '\(name)' couldn't be read: \(reason)"
        case .tooLarge: "This file is larger than the 256 MB limit."
        }
    }
}
