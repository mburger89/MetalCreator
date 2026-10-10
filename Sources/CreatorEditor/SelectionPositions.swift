import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Where the selected items were when a drag began, in stored (left-to-right) canvas points: what a move offsets
/// and an ⌥-drag copies. A comment's position is its frame's origin.
public struct SelectionPositions: Equatable, Sendable {
    public var nodes: [NodeID: Vector2]
    public var comments: [CommentID: Vector2]

    public init(nodes: [NodeID: Vector2] = [:], comments: [CommentID: Vector2] = [:]) {
        self.nodes = nodes
        self.comments = comments
    }

    public var isEmpty: Bool { nodes.isEmpty && comments.isEmpty }

    /// The items these positions are of.
    public var items: CanvasSelection { CanvasSelection(nodes: Set(nodes.keys), comments: Set(comments.keys)) }
}
