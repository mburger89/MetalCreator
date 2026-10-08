import CreatorGeometry
import CreatorGraph

/// Which way the graph flows, from the dock (spec §6.2). Node positions are stored
/// left-to-right; the vertical flow shows their transpose (x↔y), so switching docks is lossless.
public enum CanvasFlow: Sendable, Equatable {
    /// Docked at the bottom: inputs on the left edge, outputs on the right.
    case horizontal
    /// Docked left: inputs on the top edge, outputs on the bottom.
    case vertical

    /// The flow for a dock. A hidden panel keeps the left dock's flow.
    public init(_ dock: DockSide) {
        self = dock == .bottom ? .horizontal : .vertical
    }

    /// A stored (left-to-right) position as drawn in this flow.
    public func display(_ stored: Vector2) -> Vector2 {
        self == .horizontal ? stored : Vector2(stored.y, stored.x)
    }

    /// A drawn position back in stored (left-to-right) coordinates. The transpose is its own inverse.
    public func stored(_ display: Vector2) -> Vector2 { self.display(display) }
}
