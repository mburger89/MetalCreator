/// Which node, and which broadcast item of it, is calling the kernel.
public struct NodeTag: Hashable, Sendable, Codable {
    public var node: NodeID
    public var item: Int

    public init(node: NodeID, item: Int) {
        self.node = node
        self.item = item
    }
}
