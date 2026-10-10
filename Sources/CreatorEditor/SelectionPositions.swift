import CreatorGeometry
import CreatorKernel

/// Where the selected items were when a drag began, in stored (left-to-right) canvas points: what a move offsets
/// and an ⌥-drag copies. Canvas comments (sub-project B) add their frames' origins beside the nodes.
public struct SelectionPositions: Equatable, Sendable {
    public var nodes: [NodeID: Vector2]

    public init(nodes: [NodeID: Vector2] = [:]) {
        self.nodes = nodes
    }

    public var isEmpty: Bool { nodes.isEmpty }

    /// The items these positions are of.
    public var items: CanvasSelection { CanvasSelection(nodes: Set(nodes.keys)) }
}
