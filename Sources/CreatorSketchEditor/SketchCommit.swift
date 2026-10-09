import CreatorSketch

/// One edit the sketch editor made, for the host to store as one undo step (sketcher spec §8): the whole new
/// sketch, already solved and remembered (S4 → S5 handoff), and the undo menu's description.
public struct SketchCommit: Hashable, Sendable {
    public var sketch: Sketch
    public var description: String

    public init(sketch: Sketch, description: String) {
        self.sketch = sketch
        self.description = description
    }
}
