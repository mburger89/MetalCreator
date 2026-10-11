/// One piece of a Path Mapper rule, with where it sits in the text (in characters) so a message can point at it.
struct PathRuleToken: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case openBrace, closeBrace, semicolon, arrow
        case plus, minus, times, divide, percent
        case openParen, closeParen
        /// `(i)`
        case itemIndex
        case integer(Int)
        case letter(Character)
    }

    var kind: Kind
    /// The first character of the token and the one after its last.
    var start: Int
    var end: Int
}
