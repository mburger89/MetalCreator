public enum GraphFileError: Error, Equatable, Sendable {
    /// The file was written by a newer MetalCreator.
    case newerFormat(Int)
}
