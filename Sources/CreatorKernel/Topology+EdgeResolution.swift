extension Topology {
    /// The edges a remembered key names now: its matches, or, only when it has none, the matches of its narrowed
    /// key (`EdgeKey.narrowed`), or, only when that has none either, the matches of the keys that name it by one
    /// operand at a time (`EdgeKey.operandKeys`: an edge between a merged face and a third operand's face).
    /// When several of those name edges, the one whose edge count is `count` wins if exactly one has it;
    /// otherwise the nearest count wins, then the first key in sort-key order, and the result is ambiguous.
    /// `count` is the edge count of one reference solid: leave it `nil` when the pick's count was summed across
    /// several (the sum names no operand's count). A key that matches anything is never narrowed, so a pick that resolves today resolves the same way.
    public func resolution(of key: EdgeKey, expecting count: Int? = nil) -> EdgeResolution {
        let matches = edges(matching: key)
        if !matches.isEmpty { return EdgeResolution(edges: matches) }
        if let narrowed = key.narrowed {
            let narrowedMatches = edges(matching: narrowed)
            if !narrowedMatches.isEmpty { return EdgeResolution(edges: narrowedMatches) }
        }
        let found = key.operandKeys.map { edges(matching: $0) }.filter { !$0.isEmpty }
        guard let first = found.first else { return EdgeResolution(edges: []) }
        guard found.count > 1 else { return EdgeResolution(edges: first, isSplit: true) }
        guard let count else { return EdgeResolution(edges: first, isAmbiguous: true, isSplit: true) }
        let exact = found.filter { $0.count == count }
        if exact.count == 1 { return EdgeResolution(edges: exact[0], isSplit: true) }
        let nearest = (exact.isEmpty ? found : exact).min { abs($0.count - count) < abs($1.count - count) }
        return EdgeResolution(edges: nearest ?? first, isAmbiguous: true, isSplit: true)
    }
}
