import CreatorKernel
import CreatorSketch

/// A model edge the host resolved for the Project tool (sketcher spec §8): its curve on the sketch plane, the remembered
/// pick the Sketch node stores for it, and the solid it is on.
public struct ProjectionCandidate: Hashable, Sendable {
    public var curve: ProjectedCurve
    /// `topology.picks(for: [edge])`: exactly one pick, which names the edge by its faces' tags.
    public var pick: EdgePick
    /// The viewport item the edge is on (`PickTarget.solidIndex`); the host turns it into the node that made the solid.
    public var solid: Int

    public init(curve: ProjectedCurve, pick: EdgePick, solid: Int) {
        self.curve = curve
        self.pick = pick
        self.solid = solid
    }
}
