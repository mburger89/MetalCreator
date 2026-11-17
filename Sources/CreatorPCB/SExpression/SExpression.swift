/// A KiCad S-expression: the file format of `.kicad_pcb` boards.
public indirect enum SExpression: Hashable, Sendable {
    /// A list; its first element is usually the keyword atom.
    case list([SExpression])
    /// A bare token: keyword, number or unquoted name.
    case atom(String)
    /// A quoted string (escapes decoded) or a `|…|` data token's text.
    case string(String)
}

public extension SExpression {
    /// The first atom of a list.
    var keyword: String? {
        if case .list(let items) = self, case .atom(let name)? = items.first { return name }
        return nil
    }

    /// The first child list with that keyword.
    func child(_ keyword: String) -> SExpression? {
        guard case .list(let items) = self else { return nil }
        return items.first { $0.keyword == keyword }
    }

    /// Every child list with that keyword, in file order.
    func children(_ keyword: String) -> [SExpression] {
        guard case .list(let items) = self else { return [] }
        return items.filter { $0.keyword == keyword }
    }

    /// The atom or string at `index` of a list (0 is the keyword).
    func text(at index: Int) -> String? {
        guard case .list(let items) = self, items.indices.contains(index) else { return nil }
        switch items[index] {
        case .atom(let text), .string(let text): return text
        case .list: return nil
        }
    }

    /// The number at `index`, read from an atom or a string.
    func number(at index: Int) -> Double? {
        guard let text = text(at: index), let value = Double(text), value.isFinite else { return nil }
        return value
    }

    /// True for a child list `(name)`, a bare atom `name` among the elements, or `(name yes)`; false for `(name no)`.
    func hasFlag(_ name: String) -> Bool {
        guard case .list(let items) = self else { return false }
        for item in items {
            switch item {
            case .atom(let text) where text == name:
                return true
            case .list(let inner) where item.keyword == name:
                if inner.count == 1 { return true }
                return item.text(at: 1) != "no"
            default:
                continue
            }
        }
        return false
    }
}
