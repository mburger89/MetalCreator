import CreatorGeometry
import Foundation

/// Arcs and loops as the chainer needs them.
enum ArcGeometry {
    /// A line when the three points are collinear within 1e-9, else the arc through them, running the way the
    /// turn start to mid to end goes (clockwise has `end < start`).
    static func arc(start: Vector2, mid: Vector2, end: Vector2) -> Segment2D {
        let ab = mid - start, ac = end - start
        if ac.length <= 1e-9, ab.length > 1e-9 {
            // The same point twice and a distinct middle: a full circle with that diameter.
            let centre = start + ab * 0.5
            let first = atan2(start.y - centre.y, start.x - centre.x)
            return .arc(center: centre, radius: ab.length / 2, start: Angle(radians: first),
                        end: Angle(radians: first + 2 * .pi))
        }
        let determinant = 2 * (ab.x * ac.y - ab.y * ac.x)
        guard abs(determinant) >= 1e-9 * ab.length * ac.length else { return .line(start, end) }
        let abSquared = ab.x * ab.x + ab.y * ab.y
        let acSquared = ac.x * ac.x + ac.y * ac.y
        let offset = Vector2((ac.y * abSquared - ab.y * acSquared) / determinant,
                             (ab.x * acSquared - ac.x * abSquared) / determinant)
        guard offset.length <= 1e6 else { return .line(start, end) }
        let centre = start + offset
        let radius = offset.length
        let first = atan2(start.y - centre.y, start.x - centre.x)
        let last = atan2(end.y - centre.y, end.x - centre.x)
        let turn = ab.x * (end.y - mid.y) - ab.y * (end.x - mid.x)
        var finish = last
        if turn > 0 {
            while finish <= first { finish += 2 * .pi }
        } else {
            while finish >= first { finish -= 2 * .pi }
        }
        return .arc(center: centre, radius: radius, start: Angle(radians: first), end: Angle(radians: finish))
    }

    static func circle(center: Vector2, radius: Double) -> Segment2D {
        .arc(center: center, radius: radius, start: Angle(radians: 0), end: Angle(radians: 2 * .pi))
    }

    static func reversed(_ segment: Segment2D) -> Segment2D {
        switch segment {
        case .line(let start, let end): return .line(end, start)
        case .arc(let center, let radius, let start, let end): return .arc(center: center, radius: radius, start: end, end: start)
        case .spline(let curve): return .spline(curve.reversed())
        }
    }

    /// Points along a segment, both ends included; arcs are cut so no chord is off the curve by more than 0.5 micron.
    static func polyline(_ segment: Segment2D) -> [Vector2] {
        switch segment {
        case .line(let start, let end):
            return [start, end]
        case .spline(let curve):
            return curve.polyline()
        case .arc(let center, let radius, let start, let end):
            let sweep = end.radians - start.radians
            let step = radius > 0.001 ? 2 * acos(max(0, 1 - 0.0005 / radius)) : .pi / 4
            let count = min(2_048, max(8, Int((abs(sweep) / max(step, 1e-6)).rounded(.up))))
            return (0...count).map { index in
                let angle = start.radians + sweep * Double(index) / Double(count)
                return center + Vector2(cos(angle) * radius, sin(angle) * radius)
            }
        }
    }

    /// The signed area of a closed loop, counter-clockwise positive; arcs exactly, splines by their polyline.
    static func signedArea(_ loop: [Segment2D]) -> Double {
        var twice = 0.0
        for segment in loop {
            switch segment {
            case .arc(let center, let radius, let start, let end):
                let t0 = start.radians, t1 = end.radians
                twice += radius * center.x * (sin(t1) - sin(t0)) - radius * center.y * (cos(t1) - cos(t0))
                    + radius * radius * (t1 - t0)
            default:
                let points = polyline(segment)
                for (a, b) in zip(points, points.dropFirst()) { twice += a.x * b.y - b.x * a.y }
            }
        }
        return twice / 2
    }
}
