import CreatorKernel

/// Per-iteration context handed to `NodeDefinition.evaluate`.
public struct EvalContext: Sendable {
    public let node: Node
    public let item: Int
    public let parameters: [ParameterID: ConstantValue]
    /// True when a tree on an item or list socket made the node run once per branch (`BroadcastPlan.nestedPlan`), so the
    /// lists it receives are one branch's, not the whole input.
    public let isTreeRun: Bool
    /// The evaluator's cache of kernel distances for fields (fields spec §2.2), shared by every node it runs. A context
    /// made by hand (tests) gets a cache of its own.
    public let fieldDistances: FieldDistanceCache

    public init(node: Node, item: Int, parameters: [ParameterID: ConstantValue], isTreeRun: Bool = false,
                fieldDistances: FieldDistanceCache = FieldDistanceCache()) {
        self.node = node
        self.item = item
        self.parameters = parameters
        self.isTreeRun = isTreeRun
        self.fieldDistances = fieldDistances
    }

    /// The tag kernel calls should use, so created faces are named after this node and item.
    public var tag: NodeTag { NodeTag(node: node.id, item: item) }
}
