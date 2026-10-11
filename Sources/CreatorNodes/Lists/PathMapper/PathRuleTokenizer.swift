/// Cuts a Path Mapper rule into tokens. Spaces are ignored. `→` or `->` separates source and target; `-` or `−` and `*` or
/// `×` are the same operators; `(i)` is one token.
enum PathRuleTokenizer {
    static func tokens(of text: String) throws -> [PathRuleToken] {
        let characters = Array(text)
        var tokens: [PathRuleToken] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
            } else if character.isNumber, character.isASCII {
                var end = index
                while end < characters.count, characters[end].isASCII, characters[end].isNumber { end += 1 }
                let digits = String(characters[index..<end])
                guard let value = Int(digits) else { throw PathRuleError("“\(digits)” is too large to be in a path.") }
                tokens.append(PathRuleToken(kind: .integer(value), start: index, end: end))
                index = end
            } else if character == "(", let close = itemIndexEnd(characters, from: index) {
                tokens.append(PathRuleToken(kind: .itemIndex, start: index, end: close))
                index = close
            } else if character == "-", index + 1 < characters.count, characters[index + 1] == ">" {
                tokens.append(PathRuleToken(kind: .arrow, start: index, end: index + 2))
                index += 2
            } else if let kind = symbol(character) {
                tokens.append(PathRuleToken(kind: kind, start: index, end: index + 1))
                index += 1
            } else if character.isASCII, character.isLetter {
                tokens.append(PathRuleToken(kind: .letter(character), start: index, end: index + 1))
                index += 1
            } else {
                throw PathRuleError("Can't read “\(character)” in the rule (character \(index + 1)).")
            }
        }
        return tokens
    }

    private static let symbols: [Character: PathRuleToken.Kind] = [
        "{": .openBrace, "}": .closeBrace, ";": .semicolon, "→": .arrow,
        "+": .plus, "-": .minus, "−": .minus, "*": .times, "×": .times, "/": .divide, "%": .percent,
        "(": .openParen, ")": .closeParen,
    ]

    private static func symbol(_ character: Character) -> PathRuleToken.Kind? { symbols[character] }

    /// Where `(i)` ends (the index after its `)`), allowing spaces inside, or `nil` if `characters[start...]` isn't it.
    private static func itemIndexEnd(_ characters: [Character], from start: Int) -> Int? {
        var index = start + 1
        while index < characters.count, characters[index] == " " { index += 1 }
        guard index < characters.count, characters[index] == "i" else { return nil }
        index += 1
        while index < characters.count, characters[index] == " " { index += 1 }
        guard index < characters.count, characters[index] == ")" else { return nil }
        return index + 1
    }
}
