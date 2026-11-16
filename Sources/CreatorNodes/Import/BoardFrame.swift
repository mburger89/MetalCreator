import Foundation
import CreatorGeometry
import CreatorPCB

/// The outline in the board's own frame: every point moved by `-origin`, and the bounds of what is left.
enum BoardFrame {
    static func moved(_ segment: Segment2D, by shift: Vector2) -> Segment2D {
        switch segment {
        case .line(let a, let b): .line(a - shift, b - shift)
        case .arc(let center, let radius, let start, let end): .arc(center: center - shift, radius: radius, start: start, end: end)
        case .spline(let curve):
            .spline(SplineCurve2D(poles: curve.poles.map { $0 - shift }, knots: curve.knots, multiplicities: curve.multiplicities))
        }
    }

    /// The box of the outer loop: an arc counts only the quarter points inside its sweep, a spline its poles.
    static func bounds(of loop: [Segment2D]) -> (min: Vector2, max: Vector2)? {
        var points: [Vector2] = []
        for segment in loop {
            switch segment {
            case .line(let a, let b): points += [a, b]
            case .spline(let curve): points += curve.poles
            case .arc(let center, let radius, let start, let end):
                points += [segment.startPoint, segment.endPoint]
                let (low, high) = (min(start.radians, end.radians), max(start.radians, end.radians))
                if high - low >= 2 * .pi - 1e-12 {
                    points += [Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius)].map { center + $0 }
                } else {
                    for quarter in -8...8 {
                        let angle = Double(quarter) * .pi / 2
                        if angle > low, angle < high {
                            points.append(center + Vector2(cos(angle), sin(angle)) * radius)
                        }
                    }
                }
            }
        }
        guard var low = points.first else { return nil }
        var high = low
        for p in points {
            low = Vector2(min(low.x, p.x), min(low.y, p.y))
            high = Vector2(max(high.x, p.x), max(high.y, p.y))
        }
        return (low, high)
    }
}
