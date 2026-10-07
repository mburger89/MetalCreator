import CreatorKernel

/// One end of a wire: a node and one of its sockets.
public struct Endpoint: Hashable, Sendable, Codable {
    public var node: NodeID
    public var socket: SocketName

    public init(node: NodeID, socket: SocketName) {
        self.node = node
        self.socket = socket
    }
}
