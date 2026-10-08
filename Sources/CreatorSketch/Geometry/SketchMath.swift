import CreatorGeometry
import Foundation

/// Small 2D helpers. Kept as statics, not `Vector2` extensions, so they can never clash with
/// members CreatorGeometry adds later.
enum SketchMath {
    static func dot(_ a: Vector2, _ b: Vector2) -> Double { a.x * b.x + a.y * b.y }

    /// The z component of the 3D cross product: positive when `b` is counter-clockwise of `a`.
    static func cross(_ a: Vector2, _ b: Vector2) -> Double { a.x * b.y - a.y * b.x }

    /// `v` rotated a quarter turn counter-clockwise.
    static func perpendicular(_ v: Vector2) -> Vector2 { Vector2(-v.y, v.x) }

    static func normalized(_ v: Vector2) -> Vector2? {
        let length = v.length
        return length > 1e-12 ? v * (1 / length) : nil
    }

    /// The polar angle of `v` in (−π, π].
    static func angle(_ v: Vector2) -> Double { atan2(v.y, v.x) }

    /// The point at polar angle `angle` on the circle around `center`.
    static func point(on center: Vector2, radius: Double, at angle: Double) -> Vector2 {
        center + Vector2(cos(angle), sin(angle)) * radius
    }

    /// `angle` wrapped into [0, 2π).
    static func wrapped(_ angle: Double) -> Double {
        let turn = 2 * Double.pi
        let value = angle.truncatingRemainder(dividingBy: turn)
        let positive = value < 0 ? value + turn : value
        return positive >= turn ? 0 : positive
    }

    /// `p` rotated by `angle` about `center`.
    static func rotated(_ p: Vector2, about center: Vector2, by angle: Double) -> Vector2 {
        let offset = p - center
        let (c, s) = (cos(angle), sin(angle))
        return center + Vector2(offset.x * c - offset.y * s, offset.x * s + offset.y * c)
    }

    /// `p` reflected in the infinite line through `a` and `b`. Returns `p` for a degenerate line.
    static func reflected(_ p: Vector2, inLineThrough a: Vector2, _ b: Vector2) -> Vector2 {
        guard let direction = normalized(b - a) else { return p }
        let offset = p - a
        let along = direction * dot(offset, direction)
        return a + along * 2 - offset
    }
}
