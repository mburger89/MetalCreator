import CreatorGeometry
import Foundation

/// The editor's 2D helpers: polylines for drawing curves, and distances for picking them.
enum EditorGeometry {
    /// Segments per full turn when a circle or an arc is drawn as a polyline.
    static let segmentsPerTurn = 72

    /// The polar angle of `v`, in (−π, π].
    static func angle(_ v: Vector2) -> Double { atan2(v.y, v.x) }

    /// `angle` wrapped into [0, 2π).
    static func wrapped(_ angle: Double) -> Double {
        let turn = 2 * Double.pi
        let value = angle.truncatingRemainder(dividingBy: turn)
        return value < 0 ? value + turn : value
    }

    /// The counter-clockwise sweep from `start` to the ray through `end` around `center`, in (0, 2π]; a full turn
    /// when the two rays coincide.
    static func sweep(center: Vector2, start: Vector2, end: Vector2) -> Double {
        let raw = wrapped(angle(end - center) - angle(start - center))
        return raw > 1e-12 ? raw : 2 * .pi
    }

    /// The arc as a polyline from `start`, counter-clockwise, ending on the ray through `end` at `start`'s radius.
    static func arcPoints(center: Vector2, start: Vector2, end: Vector2) -> [Vector2] {
        let radius = (start - center).length
        let from = angle(start - center)
        let sweep = sweep(center: center, start: start, end: end)
        let count = max(2, Int((sweep / (2 * .pi) * Double(segmentsPerTurn)).rounded(.up)))
        return (0...count).map { step in
            let at = from + sweep * Double(step) / Double(count)
            return center + Vector2(cos(at), sin(at)) * radius
        }
    }

    /// The circle as a closed polyline (its first point repeated at the end).
    static func circlePoints(center: Vector2, radius: Double) -> [Vector2] {
        (0...segmentsPerTurn).map { step in
            let at = 2 * Double.pi * Double(step) / Double(segmentsPerTurn)
            return center + Vector2(cos(at), sin(at)) * radius
        }
    }

    /// The distance from `p` to the segment `a`–`b`.
    static func distance(from p: Vector2, toSegment a: Vector2, _ b: Vector2) -> Double {
        (p - nearest(to: p, onSegment: a, b)).length
    }

    /// The point of the segment `a`–`b` nearest `p`.
    static func nearest(to p: Vector2, onSegment a: Vector2, _ b: Vector2) -> Vector2 {
        let d = b - a
        let squared = d.x * d.x + d.y * d.y
        guard squared > 0 else { return a }
        let t = min(max(((p.x - a.x) * d.x + (p.y - a.y) * d.y) / squared, 0), 1)
        return a + d * t
    }

    /// The point of the circle around `center` nearest `p` (its rightmost point when `p` is the centre).
    static func nearest(to p: Vector2, onCircle center: Vector2, radius: Double) -> Vector2 {
        let offset = p - center
        let length = offset.length
        guard length > 1e-12 else { return center + Vector2(radius, 0) }
        return center + offset * (radius / length)
    }

    /// The distance from `p` to a polyline.
    static func distance(from p: Vector2, toPolyline points: [Vector2]) -> Double {
        zip(points, points.dropFirst()).map { distance(from: p, toSegment: $0, $1) }.min() ?? .infinity
    }

    /// The arc from `a` to `b` through `p`: the centre of the circle through the three, and whether the arc runs
    /// counter-clockwise from `a` (else from `b`). `nil` when the three are in line (or two coincide).
    static func threePointArc(from a: Vector2, to b: Vector2, through p: Vector2) -> (center: Vector2, isCounterClockwise: Bool)? {
        let (u, v) = (b - a, p - a)
        let cross = u.x * v.y - u.y * v.x
        guard abs(cross) > 1e-9 * max(1, u.x * u.x + u.y * u.y, v.x * v.x + v.y * v.y) else { return nil }
        let (uu, vv) = (u.x * u.x + u.y * u.y, v.x * v.x + v.y * v.y)
        let center = a + Vector2(v.y * uu - u.y * vv, u.x * vv - v.x * uu) * (1 / (2 * cross))
        // Counter-clockwise from a to b passes the points to the right of the chord a→b.
        return (center, cross < 0)
    }
}
