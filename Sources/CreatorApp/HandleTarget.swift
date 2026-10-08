import CreatorGraph
import CreatorKernel

/// The node input a viewport handle edits.
public struct HandleTarget: Hashable, Sendable {
    public var node: NodeID
    public var socket: SocketName

    public init(node: NodeID, socket: SocketName) {
        self.node = node
        self.socket = socket
    }

    /// The handle's id in `ViewportHandle.id`, reported back by `ViewportEvents.handleChanged`.
    public var handleID: String { "\(node.rawValue.uuidString)/\(socket.rawValue)" }
}
