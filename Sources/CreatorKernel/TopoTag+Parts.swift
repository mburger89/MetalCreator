extension Set where Element == TopoTag {
    /// These tags split by the node call that made them (`TopoTag.origin`), one set per operand, ordered by
    /// sort key so the order never depends on hashing. Empty unless the tags come from at least two node calls:
    /// only a face that a union merged has tags to split.
    public var partsByOrigin: [Set<TopoTag>] {
        let groups = Dictionary(grouping: self, by: \.origin)
        guard groups.count > 1 else { return [] }
        return groups.values.map { Set($0) }.sorted { Self.sortKey($0) < Self.sortKey($1) }
    }

    private static func sortKey(_ tags: Set<TopoTag>) -> String {
        tags.map(\.sortKey).sorted().joined(separator: "+")
    }
}
