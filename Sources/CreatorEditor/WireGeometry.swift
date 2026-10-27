import CreatorGeometry
import CreatorGraph

/// A wire's cubic bezier between two points (spec §6.2): the whole of an untied wire, or one piece of a tied wire's route
/// (cable ties spec 2026-10-26 §5.1). The control points leave each end along the flow (right/left in the horizontal flow,
/// down/up in the vertical), so a wire always leaves an output forwards and enters an input forwards.
public struct WireGeometry: Hashable, Sendable {
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

    /// A piece with its four points given: a slack piece (`WireMotion.drawn`), or one moved into a view's frame.
    public init(start: Vector2, control1: Vector2, control2: Vector2, end: Vector2) {
        self.start = start
        self.control1 = control1
        self.control2 = control2
        self.end = end
    }

    /// The point at `t` along the curve: `start` at 0, `end` at 1.
    public func point(at t: Double) -> Vector2 {
        let u = 1 - t
        return start * (u * u * u) + control1 * (3 * u * u * t) + control2 * (3 * u * t * t) + end * (t * t * t)
    }

    /// A rectangle holding the whole curve (it lies inside its control points' hull), grown
    /// by `padding` for the stroke.
    public func bounds(padding: Double) -> CanvasRect {
        let points = [start, control1, control2, end]
        let low = Vector2(points.map(\.x).min() ?? 0, points.map(\.y).min() ?? 0)
        let high = Vector2(points.map(\.x).max() ?? 0, points.map(\.y).max() ?? 0)
        return CanvasRect(origin: low - Vector2(padding, padding), size: high - low + Vector2(2 * padding, 2 * padding))
    }

    /// A rectangle holding every piece, grown by `padding`; an empty rectangle at the origin for none.
    public static func bounds(of pieces: [WireGeometry], padding: Double) -> CanvasRect {
        let boxes = pieces.map { $0.bounds(padding: padding) }
        guard let first = boxes.first else { return CanvasRect(origin: .zero, size: .zero) }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }
}
