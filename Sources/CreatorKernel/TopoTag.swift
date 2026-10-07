/// A face's name: the node that made it, the broadcast item, and its role.
public struct TopoTag: Hashable, Sendable {
    public var node: NodeID
    public var item: Int
    public var role: TopoRole

    public init(node: NodeID, item: Int, role: TopoRole) {
        self.node = node
        self.item = item
        self.role = role
    }

    public init(_ tag: NodeTag, _ role: TopoRole) {
        self.init(node: tag.node, item: tag.item, role: role)
    }

    public var sortKey: String { "\(node.rawValue.uuidString)#\(item).\(role.sortKey)" }
}
