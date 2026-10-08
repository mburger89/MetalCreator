import CreatorGeometry
import Foundation

/// Exact line/line, line/arc and arc/arc intersections (spec §5 step 2). Overlapping collinear or
/// co-circular spans report the endpoints of each that lie on the other, which is where the
/// spans must be split for their pieces to merge.
enum CurveIntersection {
    /// Points closer than this are the same point (mm).
    static let tolerance = 1e-9

    /// The points where `a` and `b` meet, without duplicates, in a fixed order.
    static func points(_ a: CurveShape, _ b: CurveShape) -> [Vector2] {
        var found: [Vector2] = []
        switch (a, b) {
        case (.line(let p, let q), .line(let r, let s)):
            found = lineLine(p, q, r, s)
        case (.line(let p, let q), .arc(let center, let radius, _, _)), (.arc(let center, let radius, _, _), .line(let p, let q)):
            found = lineCircle(p, q, center, radius)
        case (.arc(let c1, let r1, _, _), .arc(let c2, let r2, _, _)):
            found = circleCircle(c1, r1, c2, r2)
        }
        // Endpoints touching the other curve: T-junctions, overlaps and tangent touches whose
        // computed point drifted by rounding.
        found += [a.startPoint, a.endPoint].filter { b.contains($0, tolerance: tolerance) }
        found += [b.startPoint, b.endPoint].filter { a.contains($0, tolerance: tolerance) }
        var unique: [Vector2] = []
        for point in found where a.contains(point, tolerance: tolerance * 10) && b.contains(point, tolerance: tolerance * 10) {
            if !unique.contains(where: { ($0 - point).length <= tolerance }) { unique.append(point) }
        }
        return unique
    }

    /// The crossing of two segments' lines, when they are not parallel.
    static func lineLine(_ p: Vector2, _ q: Vector2, _ r: Vector2, _ s: Vector2) -> [Vector2] {
        let (d1, d2) = (q - p, s - r)
        let denominator = SketchMath.cross(d1, d2)
        guard abs(denominator) > 1e-15 * max(1, d1.length * d2.length) else { return [] }
        let t = SketchMath.cross(r - p, d2) / denominator
        return [p + d1 * t]
    }

    /// Where the infinite line through p, q meets the circle: two points, or one when tangent.
    static func lineCircle(_ p: Vector2, _ q: Vector2, _ center: Vector2, _ radius: Double) -> [Vector2] {
        guard let unit = SketchMath.normalized(q - p) else { return [] }
        let foot = p + unit * SketchMath.dot(center - p, unit)
        let h = (center - foot).length
        if h > radius + tolerance { return [] }
        if abs(h - radius) <= tolerance { return [foot] }
        let half = (radius * radius - h * h).squareRoot()
        return [foot - unit * half, foot + unit * half]
    }

    /// Where two circles meet: two points, one when tangent, none when apart, nested or concentric.
    static func circleCircle(_ c1: Vector2, _ r1: Double, _ c2: Vector2, _ r2: Double) -> [Vector2] {
        let d = (c2 - c1).length
        guard d > tolerance else { return [] }
        if d > r1 + r2 + tolerance || d < abs(r1 - r2) - tolerance { return [] }
        let unit = (c2 - c1) * (1 / d)
        let a = (d * d + r1 * r1 - r2 * r2) / (2 * d)
        let base = c1 + unit * a
        let hSquared = r1 * r1 - a * a
        if hSquared <= tolerance * tolerance { return [base] }
        let h = hSquared.squareRoot()
        let normal = SketchMath.perpendicular(unit)
        return [base + normal * h, base - normal * h]
    }
}
