/// Why a zip could not be written or read.
public enum ZipError: Error, Equatable, Sendable {
    /// The writer was used out of order (an entry written to before it was opened): a bug in the caller, reported rather than trapped.
    case misuse(String)
    case compressionFailed
    case notAZip
    case missingEntry(String)
    case checksumMismatch(String)
    case unsupportedMethod(String)
    case writeFailed(String)
    case tooLarge(String)
    case encrypted(String)
    case overlappingEntries

    public var userMessage: String {
        switch self {
        case .misuse(let what):
            "The file couldn't be written: \(what)."
        case .compressionFailed:
            "The 3MF file couldn't be compressed."
        case .notAZip:
            "The file is not a zip."
        case .missingEntry(let name):
            "The zip has no “\(name)”."
        case .checksumMismatch(let name):
            "“\(name)” in the zip is damaged."
        case .unsupportedMethod(let name):
            "“\(name)” in the zip is compressed in a way this build can't read."
        case .tooLarge(let name):
            "“\(name)” in the zip is too large to open."
        case .encrypted(let name):
            "“\(name)” in the zip is password protected, which this app can't open."
        case .overlappingEntries:
            "The zip is damaged: its entries overlap."
        case .writeFailed(let reason):
            "The file couldn't be written: \(reason)"
        }
    }
}
