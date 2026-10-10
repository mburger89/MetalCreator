/// One group node of a definition, and the graph it sits in.
public struct GroupInstance: Sendable, Equatable {
    public var path: GraphPath
    public var node: Node

    public init(path: GraphPath, node: Node) {
        self.path = path
        self.node = node
    }
}
