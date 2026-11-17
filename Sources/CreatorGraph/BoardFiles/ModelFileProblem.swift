/// Why a 3D model file could not be read from disk, as the phrase that finishes a sentence ("…because it wasn't found").
public enum ModelFileProblem: Error, Equatable, Sendable {
    case missing
    case notAFile
    case tooLarge(limit: Int)
    case unreadable(String)

    public var reason: String {
        switch self {
        case .missing: "it wasn't found"
        case .notAFile: "it isn't a file"
        case .tooLarge(let limit): "it is larger than \(limit >> 20) MB"
        case .unreadable(let words): words
        }
    }
}
