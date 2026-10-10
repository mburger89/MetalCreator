import CreatorSketch

/// One edit the sketch editor made, for the host to store as one undo step (sketcher spec §8): the whole new
/// sketch, already solved and remembered (S4 → S5 handoff), the undo menu's description, and, for Project, the
/// projections the edit added (their picks and solids live in the Sketch node's settings and wires, not the sketch).
public struct SketchCommit: Hashable, Sendable {
    public var sketch: Sketch
    public var description: String
    public var projections: [ProjectionWrite]

    public init(sketch: Sketch, description: String, projections: [ProjectionWrite] = []) {
        self.sketch = sketch
        self.description = description
        self.projections = projections
    }
}
