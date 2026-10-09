/// One remembered edge pick (spec §5.3, rule 5): the picked edge's key, how many edges that key
/// named when the pick was made, and, when only some of them were picked, which ones.
public struct EdgePick: Hashable, Sendable, Codable {
    public var key: EdgeKey
    /// How many edges `key` named when the pick was made. A different count later is drift (§5.3, rule 6).
    public var matchCount: Int
    /// Positions of the picked edges among the key's matches, ordered by midpoint (x, then y, then z).
    /// `nil` when every match was picked.
    public var ordinals: [Int]?
    /// How many runs (`Topology.runCount`) the key's matches formed, recorded only when every match was
    /// picked and the runs were fewer than the edges: an operation had split a picked edge. `nil` means
    /// one run per edge, and is what every pick made before runs were recorded has: such a pick still drifts
    /// when its edges become fewer runs, and no longer when a recorded edge is split into more pieces. An
    /// optional key, which older readers ignore (they then count edges, as they always did), so the file
    /// format stays 4.
    public var runCount: Int?

    public init(key: EdgeKey, matchCount: Int, ordinals: [Int]? = nil, runCount: Int? = nil) {
        self.key = key
        self.matchCount = matchCount
        self.ordinals = ordinals
        self.runCount = runCount
    }

    /// Whether `edges` matches forming `runs` runs are drift (spec §5.3, rule 6). A pick of every match
    /// drifts only when the edge count and the run count both differ from the recorded ones, so an edge
    /// that an operation splits in two, or stops splitting, is still the edge that was picked. A pick of
    /// some matches compares edges only, because its ordinals count edges.
    public func hasDrifted(matching edges: Int, inRuns runs: Int) -> Bool {
        guard edges != matchCount else { return false }
        return ordinals != nil || runs != (runCount ?? matchCount)
    }

    /// True when the key names a face by the `.unnamed` fallback, which is unstable across
    /// rebuilds. Blend faces are checked recursively: a fillet face whose source edge bordered an
    /// unnamed face is just as unstable.
    public var touchesUnnamedFace: Bool { key.first.union(key.second).contains { $0.role.isUnstable } }
}
