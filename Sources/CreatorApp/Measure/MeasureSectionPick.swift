import CreatorGeometry
import CreatorKernel
import CreatorViewport

/// Picks a section outline piece on screen (Measure part B): the nearest projected polyline within a radius.
enum MeasureSectionPick {
    /// The piece within `radius` points of `point`, nearest first; `part` indexes `parts`, `piece` indexes `section.pieces`.
    static func nearest(to point: ScreenPoint, in parts: [SectionedPart], screenPoint: (Vector3) -> ScreenPoint?,
                        radius: Double = 6) -> (part: Int, piece: Int)? {
        var best: (part: Int, piece: Int)?
        var bestDistance = radius
        for (partIndex, part) in parts.enumerated() {
            for (pieceIndex, piece) in part.section.pieces.enumerated() {
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

    private static func distance(from p: ScreenPoint, toSegment a: ScreenPoint, _ b: ScreenPoint) -> Double {
        let (dx, dy) = (b.x - a.x, b.y - a.y)
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared)) : 0
        let (cx, cy) = (a.x + t * dx, a.y + t * dy)
        return ((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy)).squareRoot()
    }
}
