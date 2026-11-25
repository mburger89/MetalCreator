import CreatorGeometry
import Foundation

extension ProjectedCurve {
    /// The exact box of the curve: arcs and ellipses by their extreme angles inside the sweep.
    public var bounds: Rect2D {
        switch self {
        case .line(let a, let b):
            return Rect2D(points: [a, b]) ?? Rect2D(min: a, max: a)
        case .polyline(let points):
            return Rect2D(points: points) ?? Rect2D(min: .zero, max: .zero)
        case .arc(let center, let radius, let start, let sweep):
            let angles = Self.extremes([0, Double.pi / 2, Double.pi, 3 * Double.pi / 2], start: start, sweep: sweep)
            let points = angles.map { Vector2(center.x + radius * cos($0), center.y + radius * sin($0)) }
            return Rect2D(points: points) ?? Rect2D(min: center, max: center)
        case .ellipse(let center, let axis, let major, let minor, let start, let sweep):
            let cross = Vector2(-axis.y, axis.x)
            func point(_ t: Double) -> Vector2 {
                Vector2(center.x + major * cos(t) * axis.x + minor * sin(t) * cross.x,
                        center.y + major * cos(t) * axis.y + minor * sin(t) * cross.y)
            }
            let atX = atan2(minor * cross.x, major * axis.x)
            let atY = atan2(minor * cross.y, major * axis.y)
            let candidates = [atX, atX + Double.pi, atY, atY + Double.pi]
            let angles = Self.extremes(candidates, start: start, sweep: sweep)
            return Rect2D(points: angles.map(point)) ?? Rect2D(min: center, max: center)
        }
    }

    /// The sweep's ends and each candidate angle that lies inside it.
    private static func extremes(_ candidates: [Double], start: Double, sweep: Double) -> [Double] {
        let full = 2 * Double.pi
        var result = [start, start + sweep]
        if abs(sweep) >= full - 1e-12 { return result + candidates }
        for angle in candidates {
            let offset = sweep >= 0 ? angle - start : start - angle
            var wrapped = offset.truncatingRemainder(dividingBy: full)
            if wrapped < 0 { wrapped += full }
            if wrapped <= abs(sweep) { result.append(angle) }
        }
        return result
    }
}

extension Projection2D {
    /// The box of every line, hidden ones too; `nil` with no lines.
    public var bounds: Rect2D? {
        lines.map(\.curve.bounds).reduce(nil) { partial, box in partial.map { $0.union(box) } ?? box }
    }

    public var estimatedBytes: Int {
        lines.reduce(0) { total, line in
            if case .polyline(let points) = line.curve { return total + 64 + 16 * points.count }
            return total + 64
        }
    }
}
