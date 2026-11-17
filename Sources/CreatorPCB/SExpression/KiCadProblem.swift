/// A KiCad file that can't be read, in words for the person (never a crash, never a raw parser message).
public struct KiCadProblem: Error, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}
