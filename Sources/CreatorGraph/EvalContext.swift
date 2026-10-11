import CreatorKernel

/// Per-iteration context handed to `NodeDefinition.evaluate`.
public struct EvalContext: Sendable {
    public let node: Node
    public let item: Int
    public let parameters: [ParameterID: ConstantValue]
    /// True when a tree on an item or list socket made the node run once per branch (`BroadcastPlan.nestedPlan`), so the
    /// lists it receives are one branch's, not the whole input.
    public let isTreeRun: Bool

    public init(node: Node, item: Int, parameters: [ParameterID: ConstantValue], isTreeRun: Bool = false) {
        self.node = node
        self.item = item
        self.parameters = parameters
        self.isTreeRun = isTreeRun
    }

    /// The tag kernel calls should use, so created faces are named after this node and item.
    public var tag: NodeTag { NodeTag(node: node.id, item: item) }
}
