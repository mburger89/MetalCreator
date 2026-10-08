import CreatorKernel

/// What lies under a point on the canvas, topmost first: a socket beats its node.
public enum CanvasHit: Equatable, Sendable {
    case socket(SocketRef)
    case node(NodeID)
    case empty
}
