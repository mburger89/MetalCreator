import CreatorGeometry
import Foundation

/// One piece of a stroke, in sheet millimetres. Angles are radians, counter-clockwise.
public enum SheetSegment: Hashable, Sendable {
    case line(Vector2, Vector2)
    case arc(center: Vector2, radius: Double, start: Double, sweep: Double)
    /// `majorAxis` is the direction of the major axis; the minor axis is that direction turned counter-clockwise.
    /// `start` and `sweep` are in the ellipse's parameter.
    case ellipse(center: Vector2, majorAxis: Vector2, majorRadius: Double, minorRadius: Double, start: Double, sweep: Double)
    case polyline([Vector2])

    /// The segment scaled by `scale` about the origin, then moved by `offset`.
    public func transformed(scale: Double, offset: Vector2) -> SheetSegment {
        func move(_ p: Vector2) -> Vector2 { p * scale + offset }
        switch self {
        case let .line(a, b): return .line(move(a), move(b))
        case let .arc(center, radius, start, sweep):
            return .arc(center: move(center), radius: radius * scale, start: start, sweep: sweep)
        case let .ellipse(center, axis, major, minor, start, sweep):
            return .ellipse(
                center: move(center), majorAxis: axis, majorRadius: major * scale, minorRadius: minor * scale, start: start,
                sweep: sweep)
        case let .polyline(points): return .polyline(points.map(move))
        }
    }

    /// The smallest rectangle holding the segment.
    public var bounds: Rect2D {
        switch self {
        case let .line(a, b): return Rect2D(points: [a, b]) ?? Rect2D(min: a, max: a)
        case let .polyline(points): return Rect2D(points: points) ?? Rect2D(min: .zero, max: .zero)
        case let .arc(center, radius, start, sweep):
            return Self.ellipseBounds(
                center: center, axis: Vector2(1, 0), major: radius, minor: radius, start: start, sweep: sweep)
        case let .ellipse(center, axis, major, minor, start, sweep):
            return Self.ellipseBounds(center: center, axis: axis, major: major, minor: minor, start: start, sweep: sweep)
        }
    }

    private static func unit(_ axis: Vector2) -> Vector2 {
        let length = axis.length
        return length > 0 ? Vector2(axis.x / length, axis.y / length) : Vector2(1, 0)
    }

    /// The point at parameter `t` of an ellipse whose axes are `u` (major, unit) and its counter-clockwise normal.
    static func point(center: Vector2, u: Vector2, major: Double, minor: Double, at t: Double) -> Vector2 {
        let v = Vector2(-u.y, u.x)
        let c = cos(t) * major, s = sin(t) * minor
        return Vector2(center.x + u.x * c + v.x * s, center.y + u.y * c + v.y * s)
    }

    private static func ellipseBounds(
        center: Vector2, axis: Vector2, major: Double, minor: Double, start: Double, sweep: Double
    ) -> Rect2D {
        let u = unit(axis)
        var candidates = [start, start + sweep]
        // Parameters where x or y stops changing, a half turn apart.
        let tx = atan2(-minor * u.y, major * u.x)
        let ty = atan2(minor * u.x, major * u.y)
        for base in [tx, ty] { for k in 0..<2 { candidates.append(base + Double(k) * .pi) } }
        var points: [Vector2] = []
        for (index, t) in candidates.enumerated() where index < 2 || contains(t, start: start, sweep: sweep) {
            points.append(point(center: center, u: u, major: major, minor: minor, at: t))
        }
        // The axis-aligned extremes are exact when the major axis is a coordinate direction.
        if abs(u.x) == 1 || abs(u.y) == 1 {
            for k in 0..<4 where contains(Double(k) * .pi / 2, start: start, sweep: sweep) {
                points.append(exactAxisPoint(center: center, u: u, major: major, minor: minor, quarter: k))
            }
        }
        return Rect2D(points: points) ?? Rect2D(min: center, max: center)
    }

    private static func exactAxisPoint(center: Vector2, u: Vector2, major: Double, minor: Double, quarter: Int) -> Vector2 {
        let v = Vector2(-u.y, u.x)
        switch quarter {
        case 0: return Vector2(center.x + u.x * major, center.y + u.y * major)
        case 1: return Vector2(center.x + v.x * minor, center.y + v.y * minor)
        case 2: return Vector2(center.x - u.x * major, center.y - u.y * major)
        default: return Vector2(center.x - v.x * minor, center.y - v.y * minor)
        }
    }

    /// Whether the angle `t` lies on the arc from `start` through `sweep` (either direction, a full turn included).
    private static func contains(_ t: Double, start: Double, sweep: Double) -> Bool {
        let full = 2 * Double.pi
        if abs(sweep) >= full - 1e-12 { return true }
        let tolerance = 1e-12
        var delta = sweep >= 0 ? t - start : start - t
        delta = delta.truncatingRemainder(dividingBy: full)
        if delta < -tolerance { delta += full }
        if delta < 0 { delta = 0 }
        return delta <= abs(sweep) + tolerance
    }
}
