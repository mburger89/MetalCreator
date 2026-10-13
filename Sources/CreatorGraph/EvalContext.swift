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
    /// Where a node finds the bytes behind an `ImageReference` (fields spec §5): the document's embedded images and the folder
    /// it is saved in. A context made by hand (tests) has none, so every image is absent.
    public let images: ImageResolver

    public init(node: Node, item: Int, parameters: [ParameterID: ConstantValue], isTreeRun: Bool = false,
                fieldDistances: FieldDistanceCache = FieldDistanceCache(), images: ImageResolver = ImageResolver()) {
        self.node = node
        self.item = item
        self.parameters = parameters
        self.isTreeRun = isTreeRun
        self.fieldDistances = fieldDistances
        self.images = images
    }

    /// The tag kernel calls should use, so created faces are named after this node and item.
    public var tag: NodeTag { NodeTag(node: node.id, item: item) }
}
