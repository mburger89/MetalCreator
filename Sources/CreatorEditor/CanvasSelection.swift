import CreatorGraph
import CreatorKernel

/// What is selected on the canvas (spec 2026-10-09 §3, §7; cable ties spec 2026-10-26 §4.1): nodes, canvas comments, wires
/// and cable ties. View state: never undone, never saved. Every gesture and key built on this type takes the new kinds in
/// unchanged.
public struct CanvasSelection: Equatable, Sendable {
    public var nodes: Set<NodeID>
    /// Sticky notes and comment frames alike.
    public var comments: Set<CommentID>
    /// Wires, each named by its input endpoint.
    public var wires: Set<Endpoint>
    public var ties: Set<TieID>

    public init(nodes: Set<NodeID> = [], comments: Set<CommentID> = [], wires: Set<Endpoint> = [], ties: Set<TieID> = []) {
        self.nodes = nodes
        self.comments = comments
        self.wires = wires
        self.ties = ties
    }

    public var isEmpty: Bool { nodes.isEmpty && comments.isEmpty && wires.isEmpty && ties.isEmpty }

    /// Whether every item of `other` is selected here.
    public func isSuperset(of other: CanvasSelection) -> Bool {
        nodes.isSuperset(of: other.nodes) && comments.isSuperset(of: other.comments) && wires.isSuperset(of: other.wires)
            && ties.isSuperset(of: other.ties)
    }

    /// This selection combined with `items` as `mode` says: replaced by them, with them added, or with each of
    /// them toggled in or out.
    public func applying(_ items: CanvasSelection, mode: SelectionMode) -> CanvasSelection {
        switch mode {
        case .replace: items
        case .add: CanvasSelection(nodes: nodes.union(items.nodes), comments: comments.union(items.comments),
                                   wires: wires.union(items.wires), ties: ties.union(items.ties))
        case .toggle: CanvasSelection(nodes: nodes.symmetricDifference(items.nodes),
                                      comments: comments.symmetricDifference(items.comments),
                                      wires: wires.symmetricDifference(items.wires),
                                      ties: ties.symmetricDifference(items.ties))
        }
    }

    /// This selection with only its wires combined with `boxed` as `mode` says: what an ⌥-box does (cable ties spec §4.1).
    /// Nodes, comments and ties stay as they are.
    public func applying(wires boxed: Set<Endpoint>, mode: SelectionMode) -> CanvasSelection {
        var result = self
        switch mode {
        case .replace: result.wires = boxed
        case .add: result.wires.formUnion(boxed)
        case .toggle: result.wires.formSymmetricDifference(boxed)
        }
        return result
    }
}
