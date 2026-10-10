import CreatorKernel

/// One projection an edit added, for the host to store beside the sketch: the Sketch node's `projection.<reference>`
/// setting takes the pick, and the solid it is on is wired into the node's `references`.
public struct ProjectionWrite: Hashable, Sendable {
    public var reference: String
    public var pick: EdgePick
    public var solid: Int

    public init(reference: String, pick: EdgePick, solid: Int) {
        self.reference = reference
        self.pick = pick
        self.solid = solid
    }
}
