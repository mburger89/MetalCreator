/// Something the app couldn't do, in words for the person using it: a short title and a sentence.
public struct AppProblem: Error, Equatable, Sendable {
    public var title: String
    public var message: String

    public init(_ title: String, _ message: String) {
        self.title = title
        self.message = message
    }
}
