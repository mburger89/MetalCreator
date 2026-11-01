import CreatorGeometry

/// The shortest distance between points and polylines, exact and in Swift (Measure follow-ups, Ruling 2): a section outline of
/// a mesh is a `MeasureElement.polyline` and a mesh pick a `.point`, so a pair of them needs no OpenCascade. A polyline's points
/// are in order, and it is closed when its last point equals its first (the closing segment is then already among its points).
/// Anything else, or a pair over `pairLimit` segment pairs, is the kernel's.
public enum PolylineDistance {
    /// Above this many segment pairs the kernel measures instead.
    public static let pairLimit = 250_000

    private enum Piece {
        case point(Vector3)
        case segments([Vector3])

        var count: Int {
            switch self {
            case .point: 1
            case .segments(let points): points.count - 1
            }
        }
    }

    /// The distance and the nearest point on each element (the first's witness first), or `nil` when either element is not a
    /// finite point or a polyline of at least two finite points, or the pair is over the limit.
    public static func shortest(_ first: MeasureElement, _ second: MeasureElement) -> ShapeDistance? {
        guard let a = piece(first), let b = piece(second), a.count * b.count <= pairLimit else { return nil }
        switch (a, b) {
        case (.point(let p), .point(let q)):
            return ShapeDistance(distance: (p - q).length, from: p, to: q)
        case (.point(let p), .segments(let points)):
            return nearest(points) { start, end in (p, closest(on: start, end, to: p)) }
        case (.segments(let points), .point(let q)):
            return nearest(points) { start, end in (closest(on: start, end, to: q), q) }
        case (.segments(let one), .segments(let other)):
            var best: ShapeDistance?
            for (a0, a1) in zip(one, one.dropFirst()) {
                let found = nearest(other) { b0, b1 in closestPoints(a0, a1, b0, b1) }
                if found?.distance ?? .infinity < best?.distance ?? .infinity { best = found }
            }
            return best
        }
    }

    /// The closest of `pair` over every segment of `points`.
    private static func nearest(_ points: [Vector3], _ pair: (Vector3, Vector3) -> (Vector3, Vector3)) -> ShapeDistance? {
        var best: ShapeDistance?
        for (start, end) in zip(points, points.dropFirst()) {
            let (p, q) = pair(start, end)
            let found = ShapeDistance(distance: (p - q).length, from: p, to: q)
            if found.distance < best?.distance ?? .infinity { best = found }
        }
        return best
    }

    private static func piece(_ element: MeasureElement) -> Piece? {
        switch element {
        case .point(let point):
            return point.isFinite ? .point(point) : nil
        case .polyline(let points):
            return points.count >= 2 && points.allSatisfy(\.isFinite) ? .segments(points) : nil
        case .face, .edge, .curve:
            return nil
        }
    }

    private static func closest(on start: Vector3, _ end: Vector3, to point: Vector3) -> Vector3 {
        let d = end - start
        let lengthSquared = d.dot(d)
        guard lengthSquared > 0 else { return start }
        let t = min(max((point - start).dot(d) / lengthSquared, 0), 1)
        return start + d * t
    }

    /// The closest points of two segments (Ericson, Real-Time Collision Detection 5.1.9); parallel and degenerate segments included.
    private static func closestPoints(_ p1: Vector3, _ q1: Vector3, _ p2: Vector3, _ q2: Vector3) -> (Vector3, Vector3) {
        let d1 = q1 - p1, d2 = q2 - p2, r = p1 - p2
        let a = d1.dot(d1), e = d2.dot(d2), f = d2.dot(r)
        let epsilon = 1e-12
        var s = 0.0, t = 0.0
        if a <= epsilon && e <= epsilon {
            return (p1, p2)
        } else if a <= epsilon {
            t = min(max(f / e, 0), 1)
        } else {
            let c = d1.dot(r)
            if e <= epsilon {
                s = min(max(-c / a, 0), 1)
            } else {
                let b = d1.dot(d2)
                let denominator = a * e - b * b
                s = denominator > epsilon ? min(max((b * f - c * e) / denominator, 0), 1) : 0
                t = (b * s + f) / e
                if t < 0 {
                    t = 0
                    s = min(max(-c / a, 0), 1)
                } else if t > 1 {
                    t = 1
                    s = min(max((b - c) / a, 0), 1)
                }
            }
        }
        return (p1 + d1 * s, p2 + d2 * t)
    }
}
