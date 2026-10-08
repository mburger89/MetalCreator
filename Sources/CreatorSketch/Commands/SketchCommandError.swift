/// A command that can't be applied, with a plain-language reason.
public struct SketchCommandError: Error, Hashable, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }
}
