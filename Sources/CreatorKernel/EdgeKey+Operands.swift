extension EdgeKey {
    /// The keys that name this key's edge by one operand at a time, for a side that `narrowed` can't cut down.
    ///
    /// A side that a union merged from several operands (`Set<TopoTag>.partsByOrigin`) has tags from node calls
    /// the other side knows nothing about when the edge runs between that side and a third operand's face: the rim
    /// of a hole drilled through a plate side that a flange side was merged into is `{plate.side, flange.side} |
    /// {hole.wall}`, and the hole wall shares no node call with either. Each such side is replaced by each
    /// operand's tags in turn, and the keys are returned in sort-key order, so the order never depends on hashing.
    /// A side with a node call in common with the other side is left alone (that is `narrowed`'s case), so an edge
    /// where two operands meet is never turned into an edge of one of them. Empty when no side can be split.
    public var operandKeys: [EdgeKey] {
        let firsts = Self.parts(first, toward: second), seconds = Self.parts(second, toward: first)
        guard firsts.count > 1 || seconds.count > 1 else { return [] }
        var seen: Set<EdgeKey> = [self]
        var keys: [EdgeKey] = []
        for a in firsts {
            for b in seconds {
                let key = EdgeKey(a, b)
                if seen.insert(key).inserted { keys.append(key) }
            }
        }
        return keys.sorted { $0.sortKey < $1.sortKey }
    }

    private static func parts(_ side: Set<TopoTag>, toward other: Set<TopoTag>) -> [Set<TopoTag>] {
        let origins = Set(other.map(\.origin))
        if side.contains(where: { origins.contains($0.origin) }) { return [side] }
        let parts = side.partsByOrigin
        return parts.isEmpty ? [side] : parts
    }
}
