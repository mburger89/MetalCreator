/// What an `EdgeKey` names in a topology now (`Topology.resolution(of:expecting:)`).
public struct EdgeResolution: Equatable, Sendable {
    /// The edges the key names, ordered by midpoint (x, then y, then z), then by ID.
    public var edges: [EdgeInfo]
    /// True when no edge had the key's tags and several operands' parts of it each name edges, so the choice
    /// between them is a guess. A caller says so, never silently (spec §5.3, rule 6).
    public var isAmbiguous: Bool
    /// True when `edges` are one operand's share of the key (`EdgeKey.operandKeys`), however many operands fit. A
    /// pick's edge ordinals were recorded against the whole key's matches, so they mean nothing among these.
    public var isSplit: Bool

    public init(edges: [EdgeInfo], isAmbiguous: Bool = false, isSplit: Bool = false) {
        self.edges = edges
        self.isAmbiguous = isAmbiguous
        self.isSplit = isSplit
    }
}
