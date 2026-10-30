import CreatorGeometry
import CreatorSketch
import Foundation

/// Triangles for a region's fill (sketcher spec §8): the loops as polylines (arcs at `EditorGeometry.segmentsPerTurn` a
/// turn), each hole bridged into the outline by a segment to the nearest vertex it can see (a bridge touches no other
/// vertex and runs along no edge, so a grid of aligned holes bridges cleanly), and the resulting weakly simple polygon
/// ear-clipped after its flat and repeated vertices are dropped. Pure. Every triangle is counter-clockwise. Degenerate
/// input (fewer than three points, or no area) gives none, and so does a region the clipper can't finish exactly: a
/// hole that no bridge reaches, a polygon with no ear left, or triangles whose areas don't add up to the polygon's. A
/// missing fill is the safe outcome; a fill drawn over a hole is not. The loops always end: each pass clips an ear or
/// gives up.
enum RegionTriangulator {
    static let epsilon = PolygonTriangulator.epsilon

    /// The region's triangles in plane coordinates, three points each.
    static func triangles(of region: SketchRegion) -> [Vector2] {
        PolygonTriangulator.triangles(outer: polyline(region.outer), holes: region.holes.map(polyline))
    }

    /// A loop's points in order: a line's start, an arc's start and the points along it up to (not including) its end,
    /// so the next segment's start is the previous one's end. Consecutive repeats are dropped.
    static func polyline(_ loop: [Segment2D]) -> [Vector2] {
        var points: [Vector2] = []
        for segment in loop {
            switch segment {
            case .line(let start, _):
                points.append(start)
            case .arc(let center, let radius, let start, let end):
                let sweep = end.radians - start.radians
                let steps = max(2, Int((abs(sweep) / (2 * .pi) * Double(EditorGeometry.segmentsPerTurn)).rounded(.up)))
                for step in 0..<steps {
                    let angle = start.radians + sweep * Double(step) / Double(steps)
                    points.append(center + Vector2(cos(angle), sin(angle)) * radius)
                }
            }
        }
        var distinct: [Vector2] = []
        for point in points where distinct.last.map({ ($0 - point).length > epsilon }) ?? true { distinct.append(point) }
        if distinct.count > 1, let first = distinct.first, let last = distinct.last, (first - last).length <= epsilon {
            distinct.removeLast()
        }
        return distinct
    }
}
