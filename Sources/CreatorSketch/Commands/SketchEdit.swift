/// The result of a sketch command (spec §3): the new sketch plus a description for undo.
public struct SketchEdit: Hashable, Sendable {
    public var sketch: Sketch
    /// For the undo menu, for example "Trim Line 2".
    public var description: String
    /// The constraints and dimensions of the original sketch the command removed (constraints
    /// first, each by ID), so the editor can say what went. A command never removes an exposed
    /// dimension; it refuses instead.
    public var removed: [SketchConstraintRef]

    public init(sketch: Sketch, description: String, removed: [SketchConstraintRef] = []) {
        self.sketch = sketch
        self.description = description
        self.removed = removed
    }
}
