/// One remembered edge pick (spec §5.3, rule 5): the picked edge's key, how many edges that key
/// named when the pick was made, and, when only some of them were picked, which ones.
public struct EdgePick: Hashable, Sendable, Codable {
    public var key: EdgeKey
    /// How many edges `key` named when the pick was made. A different count later is drift (§5.3, rule 6).
    public var matchCount: Int
    /// Positions of the picked edges among the key's matches, ordered by midpoint (x, then y, then z).
    /// `nil` when every match was picked.
    public var ordinals: [Int]?

    public init(key: EdgeKey, matchCount: Int, ordinals: [Int]? = nil) {
        self.key = key
        self.matchCount = matchCount
        self.ordinals = ordinals
    }

    /// True when the key names a face by the `.unnamed` fallback, which is unstable across
    /// rebuilds. Blend faces are checked recursively: a fillet face whose source edge bordered an
    /// unnamed face is just as unstable.
    public var touchesUnnamedFace: Bool { key.first.union(key.second).contains { $0.role.isUnstable } }
}
