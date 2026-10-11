/// Reads a Path Mapper rule (`PathRule`). Every refusal names the part of the rule that failed.
struct PathRuleParser {
    private let text: [Character]
    private let tokens: [PathRuleToken]
    private var position = 0

    static func parse(_ text: String) throws -> PathRule {
        var parser = PathRuleParser(text: text, tokens: try PathRuleTokenizer.tokens(of: text))
        return try parser.rule()
    }

    private init(text: String, tokens: [PathRuleToken]) {
        self.text = Array(text)
        self.tokens = tokens
    }

    private var current: PathRuleToken? { position < tokens.count ? tokens[position] : nil }

    private func slice(_ start: Int, _ end: Int) -> String {
        String(text[start..<end]).trimmingSpaces
    }

    private mutating func rule() throws -> PathRule {
        guard !tokens.isEmpty else { throw PathRuleError("The rule is empty. Write it like {A;B} → {B;A}.") }
        let sourceStart = current?.start ?? 0
        let sourceTerms = try path(whatItIs: "source")
        let sourceEnd = tokens[position - 1].end
        guard current?.kind == .arrow else {
            throw PathRuleError("The rule needs → between the source and the target, like {A;B} → {B;A}.")
        }
        position += 1
        let sourceText = slice(sourceStart, sourceEnd)
        let source = try sourceTerms.map { try sourceTerm($0, in: sourceText) }
        let targetStart = current?.start ?? 0
        let targetTerms = try path(whatItIs: "target")
        let targetText = slice(targetStart, tokens[position - 1].end)
        if let extra = current {
            throw PathRuleError("Unexpected “\(slice(extra.start, text.count))” after the target path.")
        }
        let bound = Set(source.compactMap { if case .letter(let letter) = $0 { letter } else { nil } })
        let target = try targetTerms.map { term -> PathRule.TargetTerm in
            if let unknown = term.expression.letters.subtracting(bound).sorted().first {
                let names = source.compactMap { if case .letter(let letter) = $0 { String(letter) } else { nil } }
                let known = names.isEmpty ? "names no letters" : "only names \(names.joined(separator: ", "))"
                throw PathRuleError("The target uses “\(unknown)”, but the source \(sourceText) \(known).")
            }
            return PathRule.TargetTerm(expression: term.expression, text: term.text)
        }
        return PathRule(source: source, target: target, sourceText: sourceText, targetText: targetText)
    }

    /// A term of a path as written: its expression and its text.
    private struct Term {
        var expression: PathExpression
        var text: String
    }

    private mutating func path(whatItIs name: String) throws -> [Term] {
        guard current?.kind == .openBrace else {
            throw PathRuleError("The \(name) must be a path in braces, like {A;B}.")
        }
        position += 1
        var terms: [Term] = []
        if current?.kind == .closeBrace {
            position += 1
            return terms
        }
        while true {
            guard let first = current else { throw PathRuleError("The \(name) path is missing its closing }.") }
            let expression = try sum()
            let last = tokens[position - 1]
            terms.append(Term(expression: expression, text: slice(first.start, last.end)))
            switch current?.kind {
            case .semicolon?: position += 1
            case .closeBrace?:
                position += 1
                return terms
            case nil: throw PathRuleError("The \(name) path is missing its closing }.")
            default:
                let stray = current.map { slice($0.start, $0.end) } ?? ""
                throw PathRuleError("Can't read “\(stray)” in the \(name) path; separate the levels with ;.")
            }
        }
    }

    private func sourceTerm(_ term: Term, in sourceText: String) throws -> PathRule.SourceTerm {
        switch term.expression {
        case .letter(let letter):
            guard letter != "i" else {
                throw PathRuleError("“i” can't be a letter in the source: (i) is the item's index. Use another letter.")
            }
            return .letter(letter)
        case .literal(let value):
            return .index(value)
        case .itemIndex:
            throw PathRuleError("“(i)” can only be used in the target, not in the source \(sourceText).")
        case .binary:
            throw PathRuleError("The source \(sourceText) can only have letters and whole numbers; “\(term.text)” is a calculation.")
        }
    }

    // MARK: expressions

    private mutating func sum() throws -> PathExpression {
        var left = try product()
        while let kind = current?.kind, kind == .plus || kind == .minus {
            position += 1
            let right = try product()
            left = .binary(kind == .plus ? .add : .subtract, left, right)
        }
        return left
    }

    private mutating func product() throws -> PathExpression {
        var left = try factor()
        while let kind = current?.kind, kind == .times || kind == .divide || kind == .percent {
            position += 1
            let right = try factor()
            left = .binary(kind == .times ? .multiply : (kind == .divide ? .divide : .remainder), left, right)
        }
        return left
    }

    private mutating func factor() throws -> PathExpression {
        guard let token = current else { throw PathRuleError("The rule ends where a number or letter was expected.") }
        switch token.kind {
        case .integer(let value):
            position += 1
            return .literal(value)
        case .letter(let letter):
            position += 1
            return .letter(letter)
        case .itemIndex:
            position += 1
            return .itemIndex
        case .openParen:
            position += 1
            let inner = try sum()
            guard current?.kind == .closeParen else { throw PathRuleError("A ( in the rule has no matching ).") }
            position += 1
            return inner
        default:
            throw PathRuleError("Expected a number or letter but found “\(slice(token.start, token.end))” (character \(token.start + 1)).")
        }
    }
}

private extension String {
    var trimmingSpaces: String {
        var characters = Substring(self)
        while characters.first == " " { characters = characters.dropFirst() }
        while characters.last == " " { characters = characters.dropLast() }
        return String(characters)
    }
}
