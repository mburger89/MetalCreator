import CreatorGeometry
import Foundation

/// One step along a loop, in traversal order. Arcs keep their traversal sense: `to < from`
/// when the loop runs clockwise along them.
struct LoopSegment: Hashable, Sendable {
    enum Geometry: Hashable, Sendable {
        case line(Vector2, Vector2)
        case arc(center: Vector2, radius: Double, from: Double, to: Double)
    }

    var geometry: Geometry
    /// The curve (index into the region graph's curves) this came from.
    var source: Int
    /// The exact graph vertices it runs between. Arc ends recomputed from angles are off by
    /// rounding (sin π ≠ 0), which would break the containment test's half-open rule.
    var start: Vector2
    var end: Vector2

    init(geometry: Geometry, source: Int, start: Vector2, end: Vector2) {
        self.geometry = geometry
        self.source = source
        self.start = start
        self.end = end
    }

    /// A segment whose ends are computed from its geometry.
    init(geometry: Geometry, source: Int) {
        let (start, end) = switch geometry {
        case .line(let a, let b): (a, b)
        case .arc(let c, let r, let from, let to): (SketchMath.point(on: c, radius: r, at: from), SketchMath.point(on: c, radius: r, at: to))
        }
        self.init(geometry: geometry, source: source, start: start, end: end)
    }

    var segment: Segment2D {
        switch geometry {
        case .line(let a, let b): .line(a, b)
        case .arc(let c, let r, let from, let to): .arc(center: c, radius: r, start: Angle(radians: from), end: Angle(radians: to))
        }
    }

    /// The point halfway along, used as a component's test point for nesting.
    var midpoint: Vector2 {
        switch geometry {
        case .line(let a, let b): (a + b) * 0.5
        case .arc(let c, let r, let from, let to): SketchMath.point(on: c, radius: r, at: (from + to) / 2)
        }
    }

    /// `next` continued into this segment, when both come from the same curve in the same sense.
    func merged(with next: LoopSegment) -> LoopSegment? {
        guard source == next.source else { return nil }
        switch (geometry, next.geometry) {
        case (.line(let a, _), .line(_, let b)):
            return LoopSegment(geometry: .line(a, b), source: source, start: start, end: next.end)
        case (.arc(let c, let r, let from, let to), .arc(_, _, let nextFrom, let nextTo)):
            guard (to - from) * (nextTo - nextFrom) > 0 else { return nil }
            return LoopSegment(geometry: .arc(center: c, radius: r, from: from, to: to + (nextTo - nextFrom)), source: source,
                               start: start, end: next.end)
        default:
            return nil
        }
    }
}
