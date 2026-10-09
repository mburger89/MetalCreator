extension TopoTag {
    /// The node call that made the tagged face: the node and its broadcast item.
    public var origin: NodeTag { NodeTag(node: node, item: item) }
}
