/// The result of a sketch command (spec §3): the new sketch plus a description for undo.
public struct SketchEdit: Hashable, Sendable {
    public var sketch: Sketch
    /// For the undo menu, for example "Trim Line 2".
    public var description: String

    public init(sketch: Sketch, description: String) {
        self.sketch = sketch
        self.description = description
    }
}
