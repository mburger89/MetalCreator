/// A projected model edge (spec §3). The edge pick itself (an M3 `EdgePick`) lives in the Sketch
/// node's settings under `reference`, because `CreatorSketch` may not import `CreatorKernel`;
/// the node resolves the pick and refreshes `curve` before solving (S4).
public struct ProjectionSource: Hashable, Sendable, Codable {
    /// The key under which the Sketch node stores this projection's edge pick.
    public var reference: String
    /// The 2D geometry from the last successful resolve, in plane coordinates.
    public var curve: ProjectedCurve
    /// True when the last resolve matched no edge or several. The solver then skips every
    /// constraint on this entity (suspended, not deleted) and regions ignore it.
    public var isSuspended: Bool

    public init(reference: String, curve: ProjectedCurve, isSuspended: Bool = false) {
        self.reference = reference
        self.curve = curve
        self.isSuspended = isSuspended
    }
}
