import CreatorGeometry
import Foundation

public enum SheetHitTest {
    static let frameGrowth = 2.0

    /// The topmost view (the last in `order`) whose frame, grown by 2 mm, holds the point.
    public static func view(at point: Vector2, in picture: SheetPicture, order: [ViewID]) -> ViewID? {
        for id in order.reversed() {
            if let frame = picture.viewFrames[id], frame.insetBy(-frameGrowth).contains(point) { return id }
        }
        return nil
    }

    /// The index into `picture.strokes` of the view's stroke nearest the point within `tolerance`.
    public static func line(near point: Vector2, in picture: SheetPicture, view: ViewID, tolerance: Double) -> Int? {
        var best: (index: Int, distance: Double)?
        for (index, stroke) in picture.strokes.enumerated() where stroke.view == view {
            let distance = stroke.segments.map { distance(from: point, to: $0) }.min() ?? .infinity
            if distance <= tolerance, distance < (best?.distance ?? .infinity) { best = (index, distance) }
        }
        return best?.index
    }

    private static func distance(from p: Vector2, to segment: SheetSegment) -> Double {
        switch segment {
        case let .line(a, b): return distance(from: p, toLine: a, b)
        case let .polyline(points): return polylineDistance(p, points)
        case let .arc(center, radius, start, sweep):
            return polylineDistance(p, sampled(center, Vector2(1, 0), radius, radius, start, sweep))
        case let .ellipse(center, axis, major, minor, start, sweep):
            let length = axis.length
            let u = length > 0 ? Vector2(axis.x / length, axis.y / length) : Vector2(1, 0)
            return polylineDistance(p, sampled(center, u, major, minor, start, sweep))
        }
    }

    private static func sampled(
        _ center: Vector2, _ u: Vector2, _ major: Double, _ minor: Double, _ start: Double, _ sweep: Double
    ) -> [Vector2] {
        let steps = Swift.max(8, Int((abs(sweep) / (2 * .pi) * 128).rounded(.up)))
        return (0...steps).map {
            SheetSegment.point(
                center: center, u: u, major: major, minor: minor, at: start + sweep * Double($0) / Double(steps))
        }
    }

    private static func polylineDistance(_ p: Vector2, _ points: [Vector2]) -> Double {
        guard var previous = points.first else { return .infinity }
        if points.count == 1 { return (p - previous).length }
        var best = Double.infinity
        for next in points.dropFirst() {
            best = Swift.min(best, distance(from: p, toLine: previous, next))
            previous = next
        }
        return best
    }

    private static func distance(from p: Vector2, toLine a: Vector2, _ b: Vector2) -> Double {
        let d = b - a
        let lengthSquared = d.x * d.x + d.y * d.y
        guard lengthSquared > 0 else { return (p - a).length }
        let t = Swift.max(0, Swift.min(1, ((p.x - a.x) * d.x + (p.y - a.y) * d.y) / lengthSquared))
        return (p - Vector2(a.x + d.x * t, a.y + d.y * t)).length
    }
}
