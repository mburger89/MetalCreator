import CreatorGeometry
import CreatorKernel
import CreatorViewport

/// Picks a section outline piece on screen (Measure part B): the nearest projected polyline within a radius.
enum MeasureSectionPick {
    /// The piece within `radius` points of `point`, nearest first; `part` indexes `parts`, `piece` indexes `section.pieces`.
    ///
    /// A piece is projected point by point only when the pointer lies within its projected world bounds grown by `radius`;
    /// a bounds corner behind the camera makes the piece always tested. `bounds` is `bounds(of:)` for `parts`, kept per scene.
    static func nearest(to point: ScreenPoint, in parts: [SectionedPart], bounds: [[Box]]? = nil,
                        screenPoint: (Vector3) -> ScreenPoint?, radius: Double = 6) -> (part: Int, piece: Int)? {
        let bounds = bounds ?? Self.bounds(of: parts)
        var best: (part: Int, piece: Int)?
        var bestDistance = radius
        for (partIndex, part) in parts.enumerated() {
            for (pieceIndex, piece) in part.section.pieces.enumerated() {
                if !mayReach(point, box: bounds[partIndex][pieceIndex], radius: bestDistance, screenPoint: screenPoint) {
                    continue
                }
                let projected = piece.polyline.map(screenPoint)
                for (a, b) in zip(projected, projected.dropFirst()) {
                    guard let a, let b else { continue }
                    let distance = distance(from: point, toSegment: a, b)
                    if distance <= bestDistance {
                        bestDistance = distance
                        best = (partIndex, pieceIndex)
                    }
                }
            }
        }
        return best
    }

    /// A piece's world bounds.
    struct Box {
        let low: Vector3
        let high: Vector3
    }

    /// The world bounds of every piece of every part, in the order of `parts` and their pieces.
    static func bounds(of parts: [SectionedPart]) -> [[Box]] {
        parts.map { part in
            part.section.pieces.map { piece in
                guard let first = piece.polyline.first else { return Box(low: .zero, high: .zero) }
                var (low, high) = (first, first)
                for p in piece.polyline {
                    low = Vector3(min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
                    high = Vector3(max(high.x, p.x), max(high.y, p.y), max(high.z, p.z))
                }
                return Box(low: low, high: high)
            }
        }
    }

    /// Whether `point` is within `radius` of the box's projection; true when any corner has no screen position.
    private static func mayReach(_ point: ScreenPoint, box: Box, radius: Double,
                                 screenPoint: (Vector3) -> ScreenPoint?) -> Bool {
        var (minX, minY, maxX, maxY) = (Double.infinity, Double.infinity, -Double.infinity, -Double.infinity)
        for x in [box.low.x, box.high.x] {
            for y in [box.low.y, box.high.y] {
                for z in [box.low.z, box.high.z] {
                    guard let s = screenPoint(Vector3(x, y, z)) else { return true }
                    (minX, minY, maxX, maxY) = (min(minX, s.x), min(minY, s.y), max(maxX, s.x), max(maxY, s.y))
                }
            }
        }
        return point.x >= minX - radius && point.x <= maxX + radius && point.y >= minY - radius && point.y <= maxY + radius
    }

    private static func distance(from p: ScreenPoint, toSegment a: ScreenPoint, _ b: ScreenPoint) -> Double {
        let (dx, dy) = (b.x - a.x, b.y - a.y)
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared)) : 0
        let (cx, cy) = (a.x + t * dx, a.y + t * dy)
        return ((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy)).squareRoot()
    }
}
