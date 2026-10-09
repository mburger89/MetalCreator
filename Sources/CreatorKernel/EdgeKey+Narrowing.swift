extension EdgeKey {
    /// This key with each side cut down to the tags whose node call (`TopoTag.origin`) the other side also
    /// has tags from, or `nil` when that changes nothing.
    ///
    /// A face a union merged carries every operand's tags (spec §5.3, rule 2), but an edge between it and a
    /// face of one operand runs along that operand's part of it: the plate's top edge on a side that a
    /// flange's coplanar side was merged into is `{plate.endCap} | {plate.side}` whatever the flange does.
    /// A side with no tag from the other side's node calls is kept whole, so an edge where two operands meet
    /// (the plate's top against the flange's face) keeps its full name and is never narrowed.
    public var narrowed: EdgeKey? {
        let key = EdgeKey(Self.narrow(first, toward: second), Self.narrow(second, toward: first))
        return key == self ? nil : key
    }

    private static func narrow(_ side: Set<TopoTag>, toward other: Set<TopoTag>) -> Set<TopoTag> {
        let origins = Set(other.map(\.origin))
        let kept = side.filter { origins.contains($0.origin) }
        return kept.isEmpty ? side : kept
    }
}
