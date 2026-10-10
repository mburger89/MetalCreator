import CreatorSketch

/// One edit the sketch editor made, for the host to store as one undo step (sketcher spec §8): the whole new
/// sketch, already solved and remembered (S4 → S5 handoff), a `description` of the edit (finer text for tests and
/// logs: it holds typed names and numbers, so it is never shown in a menu), the undo step's fixed `name`, and, for Project, the
/// projections the edit added (their picks and solids live in the Sketch node's settings and wires, not the sketch).
public struct SketchCommit: Hashable, Sendable {
    public var sketch: Sketch
    public var description: String
    /// The fixed name of the undo step (`SketchStepName`, "Add Line"): what the Edit menu shows, never typed text.
    public var name: String
    public var projections: [ProjectionWrite]

    public init(sketch: Sketch, description: String, name: String = SketchStepName.editSketch,
                projections: [ProjectionWrite] = []) {
        self.sketch = sketch
        self.description = description
        self.name = name
        self.projections = projections
    }
}
