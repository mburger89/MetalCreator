import CreatorGeometry

/// A wire being dragged out of a socket. `current` is the pointer in display canvas points.
public struct WireDrag: Equatable, Sendable {
    public var from: SocketRef
    public var current: Vector2

    public init(from: SocketRef, current: Vector2) {
        self.from = from
        self.current = current
    }
}
