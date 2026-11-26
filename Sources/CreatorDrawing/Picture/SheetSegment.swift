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
        transformed(scaleX: scale, scaleY: scale, offset: offset)
    }

    /// The segment scaled by `scaleX` and `scaleY` about the origin (a negative one mirrors), then moved by `offset`. The ends
    /// stay the ends: a mirror reverses the sweep, so the segment is traced from the same end as before.
    public func transformed(scaleX: Double, scaleY: Double, offset: Vector2) -> SheetSegment {
        func move(_ p: Vector2) -> Vector2 { Vector2(p.x * scaleX + offset.x, p.y * scaleY + offset.y) }
        switch self {
        case let .line(a, b): return .line(move(a), move(b))
        case let .polyline(points): return .polyline(points.map(move))
        case let .arc(center, radius, start, sweep):
            if scaleX == scaleY && scaleX > 0 {
                return .arc(center: move(center), radius: radius * scaleX, start: start, sweep: sweep)
            }
            return Self.ellipse(
                Ellipse(center: center, axis: Vector2(1, 0), major: radius, minor: radius, start: start, sweep: sweep),
                scaleX: scaleX, scaleY: scaleY, offset: offset)
        case let .ellipse(center, axis, major, minor, start, sweep):
            if scaleX == scaleY && scaleX > 0 {
                return .ellipse(
                    center: move(center), majorAxis: axis, majorRadius: major * scaleX, minorRadius: minor * scaleX, start: start,
                    sweep: sweep)
            }
            return Self.ellipse(
                Ellipse(center: center, axis: axis, major: major, minor: minor, start: start, sweep: sweep),
                scaleX: scaleX, scaleY: scaleY, offset: offset)
        }
    }

    private struct Ellipse {
        var center: Vector2
        var axis: Vector2
        var major: Double
        var minor: Double
        var start: Double
        var sweep: Double
    }

    /// An ellipse (or circle) through a scale: its two half-axes A = major u and B = minor v are scaled as vectors, and the
    /// scaled pair, which is no longer perpendicular for a general scale, is turned back to principal axes by a shift of the
    /// parameter. A mirror makes the pair left-handed, so the parameter runs the other way and the sweep changes sign.
    private static func ellipse(_ source: Ellipse, scaleX: Double, scaleY: Double, offset: Vector2) -> SheetSegment {
        let (center, major, minor, start, sweep) = (source.center, source.major, source.minor, source.start, source.sweep)
        let u = unit(source.axis)
        func scaled(_ v: Vector2) -> Vector2 { Vector2(v.x * scaleX, v.y * scaleY) }
        let a = scaled(u * major), b = scaled(Vector2(-u.y, u.x) * minor)
        let t0 = 0.5 * atan2(2 * (a.x * b.x + a.y * b.y), a.x * a.x + a.y * a.y - b.x * b.x - b.y * b.y)
        // The point is c + cos s A' + sin s B' for s = t - t0, with A' and B' perpendicular.
        var first = a * cos(t0) + b * sin(t0)
        var second = b * cos(t0) - a * sin(t0)
        var from = start - t0
        if second.length > first.length {
            // The long axis is B': cos s A' + sin s B' = cos u (-B') + sin u A' for s = u - pi/2.
            (first, second) = (second * -1, first)
            from += .pi / 2
        }
        let majorLength = first.length
        let middle = Vector2(center.x * scaleX + offset.x, center.y * scaleY + offset.y)
        guard majorLength > 0 else { return .line(middle, middle) }
        let direction = first * (1 / majorLength)
        let leftHanded = second.x * -direction.y + second.y * direction.x < 0
        return .ellipse(
            center: middle, majorAxis: direction, majorRadius: majorLength, minorRadius: second.length, start: leftHanded ? -from : from,
            sweep: leftHanded ? -sweep : sweep)
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
