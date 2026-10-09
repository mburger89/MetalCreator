/// A theme action that couldn't be done, as the one sentence the theme editor shows.
public struct ThemeProblem: Error, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}
