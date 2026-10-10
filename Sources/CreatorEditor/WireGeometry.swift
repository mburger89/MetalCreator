import CreatorGeometry
import CreatorGraph

/// A wire's cubic bezier between two sockets (spec §6.2). The control points leave each socket
/// along the flow — right/left in the horizontal flow, down/up in the vertical — so a wire
/// always leaves an output forwards and enters an input forwards.
public struct WireGeometry: Equatable, Sendable {
    public var start: Vector2
    public var control1: Vector2
    public var control2: Vector2
    public var end: Vector2

    /// `start` is the output end, `end` the input end, both in display canvas points.
    public init(from start: Vector2, to end: Vector2, flow: CanvasFlow) {
        let along = flow == .horizontal ? end.x - start.x : end.y - start.y
        let reach = max(40, abs(along) * 0.5)
        let step = flow == .horizontal ? Vector2(reach, 0) : Vector2(0, reach)
        self.start = start
        self.control1 = start + step
        self.control2 = end - step
        self.end = end
    }

    /// A rectangle holding the whole curve (it lies inside its control points' hull), grown
    /// by `padding` for the stroke.
    public func bounds(padding: Double) -> CanvasRect {
        let points = [start, control1, control2, end]
        let low = Vector2(points.map(\.x).min() ?? 0, points.map(\.y).min() ?? 0)
        let high = Vector2(points.map(\.x).max() ?? 0, points.map(\.y).max() ?? 0)
        return CanvasRect(origin: low - Vector2(padding, padding), size: high - low + Vector2(2 * padding, 2 * padding))
    }
}
