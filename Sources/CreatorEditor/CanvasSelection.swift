import CreatorGraph
import CreatorKernel

/// What is selected on the canvas (spec 2026-10-09 §3, §7): nodes and canvas comments. View state: never undone,
/// never saved. Every gesture and key built on this type takes comments in unchanged.
public struct CanvasSelection: Equatable, Sendable {
    public var nodes: Set<NodeID>
    /// Sticky notes and comment frames alike.
    public var comments: Set<CommentID>

    public init(nodes: Set<NodeID> = [], comments: Set<CommentID> = []) {
        self.nodes = nodes
        self.comments = comments
    }

    public var isEmpty: Bool { nodes.isEmpty && comments.isEmpty }

    /// Whether every item of `other` is selected here.
    public func isSuperset(of other: CanvasSelection) -> Bool {
        nodes.isSuperset(of: other.nodes) && comments.isSuperset(of: other.comments)
    }

    /// This selection combined with `items` as `mode` says: replaced by them, with them added, or with each of
    /// them toggled in or out.
    public func applying(_ items: CanvasSelection, mode: SelectionMode) -> CanvasSelection {
        switch mode {
        case .replace: items
        case .add: CanvasSelection(nodes: nodes.union(items.nodes), comments: comments.union(items.comments))
        case .toggle: CanvasSelection(nodes: nodes.symmetricDifference(items.nodes),
                                      comments: comments.symmetricDifference(items.comments))
        }
    }
}
