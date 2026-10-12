import Foundation

extension Profile2D {
    /// Whether `point`, in the plane's own coordinates, is on the region: inside the outer loop and outside every hole, or
    /// on a loop's line to `tolerance` (a point on the outline counts as inside). Arcs are walked as chords no more than 2°
    /// long, so an arc is found to within 0.00015 of its radius.
    public func contains(_ point: Vector2, tolerance: Double = 1e-6) -> Bool {
        var crossings = 0
        for loop in loops {
            let outline = Self.outline(of: loop)
            for (p, q) in zip(outline, outline.dropFirst()) {
                if Self.distance(from: point, toSegment: p, q) <= tolerance { return true }
                // Even-odd rule over every loop, so a hole's inside is outside the region.
                if (p.y > point.y) != (q.y > point.y), point.x < p.x + (point.y - p.y) / (q.y - p.y) * (q.x - p.x) {
                    crossings += 1
                }
            }
        }
        return crossings % 2 == 1
    }

    /// The corners of a loop, arcs cut into chords of 2° at most.
    private static func outline(of loop: [Segment2D]) -> [Vector2] {
        guard let first = loop.first else { return [] }
        var points = [first.startPoint]
        for segment in loop {
            switch segment {
            case .line(_, let end):
                points.append(end)
            case .arc(let center, let radius, let start, let end):
                let sweep = end.radians - start.radians
                let steps = max(2, Int((abs(sweep) / (.pi / 90)).rounded(.up)))
                for step in 1..<steps {
                    let angle = start.radians + sweep * Double(step) / Double(steps)
                    points.append(center + Vector2(cos(angle), sin(angle)) * radius)
                }
                points.append(segment.endPoint)
            }
        }
        return points
    }

    private static func distance(from point: Vector2, toSegment a: Vector2, _ b: Vector2) -> Double {
        let (dx, dy) = (b.x - a.x, b.y - a.y)
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return (point - a).length }
        let along = min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        return (point - (a + Vector2(dx, dy) * along)).length
    }
}
