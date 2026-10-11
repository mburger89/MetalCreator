/// A number in a Path Mapper target: integers, the letters the source binds, `(i)` and `+ − × / %` (7a spec §4).
indirect enum PathExpression: Equatable, Sendable {
    enum Operator: Equatable, Sendable {
        case add, subtract, multiply, divide, remainder
    }

    case literal(Int)
    case letter(Character)
    /// `(i)`: the item's index within its branch.
    case itemIndex
    case binary(Operator, PathExpression, PathExpression)

    /// True when `(i)` appears anywhere in the expression.
    var usesItemIndex: Bool {
        switch self {
        case .itemIndex: true
        case .binary(_, let left, let right): left.usesItemIndex || right.usesItemIndex
        case .literal, .letter: false
        }
    }

    /// Every letter in the expression.
    var letters: Set<Character> {
        switch self {
        case .letter(let letter): [letter]
        case .binary(_, let left, let right): left.letters.union(right.letters)
        case .literal, .itemIndex: []
        }
    }

    /// The value with each letter bound in `bindings` and `(i)` as `itemIndex`. Whole-number arithmetic: `/` drops the
    /// fraction. Throws for a division by zero or a result too large for a whole number; `text` is the part of the rule
    /// to name in the message.
    func value(_ bindings: [Character: Int], itemIndex: Int, text: String) throws -> Int {
        switch self {
        case .literal(let value): return value
        case .letter(let letter): return bindings[letter] ?? 0
        case .itemIndex: return itemIndex
        case .binary(let op, let left, let right):
            let (a, b) = (try left.value(bindings, itemIndex: itemIndex, text: text),
                          try right.value(bindings, itemIndex: itemIndex, text: text))
            return try op.apply(a, b, text: text)
        }
    }
}

extension PathExpression.Operator {
    /// `a` and `b` combined in whole numbers (`/` drops the fraction); throws for a division by zero or a result too
    /// large for a whole number, naming `text`.
    func apply(_ a: Int, _ b: Int, text: String) throws -> Int {
        let result: (partialValue: Int, overflow: Bool)
        switch self {
        case .add: result = a.addingReportingOverflow(b)
        case .subtract: result = a.subtractingReportingOverflow(b)
        case .multiply: result = a.multipliedReportingOverflow(by: b)
        case .divide:
            guard b != 0 else { throw PathRuleError("“\(text)” divides by zero.") }
            result = a.dividedReportingOverflow(by: b)
        case .remainder:
            guard b != 0 else { throw PathRuleError("“\(text)” divides by zero.") }
            result = a.remainderReportingOverflow(dividingBy: b)
        }
        guard !result.overflow else { throw PathRuleError("“\(text)” gives a number too large for a path.") }
        return result.partialValue
    }
}
