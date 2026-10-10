import CreatorGeometry
import CreatorKernel

/// One plain click on a node's body, remembered so the next can be told a double click (`EditorModel+DoubleClick`).
struct NodeClick: Hashable, Sendable {
    var node: NodeID
    /// Where it was, in canvas-local screen points.
    var point: Vector2
    var time: ContinuousClock.Instant
}
