import CreatorKernel

/// What is selected on the canvas (spec 2026-10-09 §3). View state: never undone, never saved. Only nodes today;
/// canvas comments (sub-project B) add a `comments` set with an empty default and fold it into every member here,
/// so every gesture and key built on this type takes them in unchanged.
public struct CanvasSelection: Equatable, Sendable {
    public var nodes: Set<NodeID>

    public init(nodes: Set<NodeID> = []) {
        self.nodes = nodes
    }

    public var isEmpty: Bool { nodes.isEmpty }

    /// Whether every item of `other` is selected here.
    public func isSuperset(of other: CanvasSelection) -> Bool {
        nodes.isSuperset(of: other.nodes)
    }

    /// This selection combined with `items` as `mode` says: replaced by them, with them added, or with each of
    /// them toggled in or out.
    public func applying(_ items: CanvasSelection, mode: SelectionMode) -> CanvasSelection {
        switch mode {
        case .replace: items
        case .add: CanvasSelection(nodes: nodes.union(items.nodes))
        case .toggle: CanvasSelection(nodes: nodes.symmetricDifference(items.nodes))
        }
    }
}
