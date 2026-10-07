import CreatorKernel

/// Per-iteration context handed to `NodeDefinition.evaluate`.
public struct EvalContext: Sendable {
    public let node: Node
    public let item: Int
    public let parameters: [ParameterID: ConstantValue]

    public init(node: Node, item: Int, parameters: [ParameterID: ConstantValue]) {
        self.node = node
        self.item = item
        self.parameters = parameters
    }

    /// The tag kernel calls should use, so created faces are named after this node and item.
    public var tag: NodeTag { NodeTag(node: node.id, item: item) }
}
