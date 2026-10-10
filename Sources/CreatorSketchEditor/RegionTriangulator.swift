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
    /// Areas and cross products below this (mm²) count as zero.
    static let epsilon = 1e-9

    /// The region's triangles in plane coordinates, three points each.
    static func triangles(of region: SketchRegion) -> [Vector2] {
        triangles(outer: polyline(region.outer), holes: region.holes.map(polyline))
    }

    /// `outer` and `holes` in either winding.
    static func triangles(outer: [Vector2], holes: [[Vector2]]) -> [Vector2] {
        guard outer.count >= 3 else { return [] }
        var polygon = oriented(outer, counterClockwise: true)
        var pending = holes.filter { $0.count >= 3 }.map { oriented($0, counterClockwise: false) }
        pending.sort { rightmost($0).point.x > rightmost($1).point.x }
        while !pending.isEmpty {
            let hole = pending.removeFirst()
            guard let merged = bridged(polygon, hole, others: pending) else { return [] }
            polygon = merged
        }
        return earClip(polygon)
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

    // MARK: - Geometry

    static func cross(_ a: Vector2, _ b: Vector2) -> Double { a.x * b.y - a.y * b.x }

    /// Twice the polygon's signed area: positive for counter-clockwise.
    static func doubleArea(_ loop: [Vector2]) -> Double {
        zip(loop, loop.dropFirst() + loop.prefix(1)).reduce(0) { $0 + cross($1.0, $1.1) }
    }

    static func oriented(_ loop: [Vector2], counterClockwise: Bool) -> [Vector2] {
        (doubleArea(loop) > 0) == counterClockwise ? loop : Array(loop.reversed())
    }

    static func rightmost(_ loop: [Vector2]) -> (index: Int, point: Vector2) {
        var best = 0
        for index in loop.indices where loop[index].x > loop[best].x { best = index }
        return (best, loop[best])
    }

    /// Whether `p` is inside the polygon (even-odd).
    static func contains(_ loop: [Vector2], _ p: Vector2) -> Bool {
        var inside = false
        for (a, b) in zip(loop, loop.dropFirst() + loop.prefix(1)) where (a.y > p.y) != (b.y > p.y) {
            if p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
        }
        return inside
    }

    /// Whether the segments `a`–`b` and `c`–`d` cross at a point inside both (touching at an end doesn't count).
    static func cross(_ a: Vector2, _ b: Vector2, _ c: Vector2, _ d: Vector2) -> Bool {
        let d1 = cross(b - a, c - a)
        let d2 = cross(b - a, d - a)
        let d3 = cross(d - c, a - c)
        let d4 = cross(d - c, b - c)
        return ((d1 > epsilon && d2 < -epsilon) || (d1 < -epsilon && d2 > epsilon))
            && ((d3 > epsilon && d4 < -epsilon) || (d3 < -epsilon && d4 > epsilon))
    }

    // MARK: - Bridging

    /// Whether `p` lies in the open wedge at `polygon[index]` that is the polygon's inside (counter-clockwise polygon).
    static func inCone(_ polygon: [Vector2], at index: Int, towards p: Vector2) -> Bool {
        let count = polygon.count
        let (before, v, after) = (polygon[(index + count - 1) % count], polygon[index], polygon[(index + 1) % count])
        if cross(v - before, after - v) >= 0 {
            return cross(after - v, p - v) > epsilon && cross(p - v, before - v) > epsilon
        }
        return !(cross(before - v, p - v) >= -epsilon && cross(p - v, after - v) >= -epsilon)
    }

    /// Whether the segment `from`–`to` touches no loop except at its ends: it crosses no edge, passes through no vertex
    /// and so runs along no edge.
    static func isClear(_ from: Vector2, _ to: Vector2, loops: [[Vector2]]) -> Bool {
        let direction = to - from
        let length = direction.length
        for loop in loops {
            for (c, d) in zip(loop, loop.dropFirst() + loop.prefix(1)) where cross(from, to, c, d) { return false }
            for v in loop where (v - from).length > epsilon && (v - to).length > epsilon {
                let offset = v - from
                let along = (offset.x * direction.x + offset.y * direction.y) / (length * length)
                if abs(cross(direction, offset)) <= epsilon * max(1, length), along > 0, along < 1 { return false }
            }
        }
        return true
    }

    /// `polygon` with `hole` joined in by a bridge: from the hole's rightmost vertex (then its others, if none works) to
    /// the nearest polygon vertex it sees (the segment is clear, leaves that vertex into the polygon's inside and runs
    /// outside the holes), or `nil` when no vertex of the hole sees one. The bridge appears twice in the result.
    static func bridged(_ polygon: [Vector2], _ hole: [Vector2], others: [[Vector2]]) -> [Vector2]? {
        let loops = [polygon, hole] + others
        for start in hole.indices.sorted(by: { hole[$0].x > hole[$1].x }) {
            let from = hole[start]
            let nearest = polygon.indices.sorted { (polygon[$0] - from).length < (polygon[$1] - from).length }
            for index in nearest {
                let to = polygon[index]
                let middle = (from + to) * 0.5
                guard (to - from).length > epsilon, inCone(polygon, at: index, towards: from), isClear(from, to, loops: loops),
                      contains(polygon, middle), !contains(hole, middle), !others.contains(where: { contains($0, middle) })
                else { continue }
                let turned = Array(hole[start...] + hole[..<start])
                return Array(polygon[...index]) + turned + [from, to] + Array(polygon[(index + 1)...])
            }
        }
        return nil
    }

    // MARK: - Ear clipping

    /// `points` without a vertex that repeats the next one or lies on the line through its neighbours, until none is left
    /// (fewer than three left: none).
    static func withoutFlatVertices(_ points: [Vector2]) -> [Vector2] {
        var ring = points
        var changed = true
        while changed, ring.count >= 3 {
            changed = false
            var index = 0
            while index < ring.count, ring.count >= 3 {
                let count = ring.count
                let (a, b, c) = (ring[(index + count - 1) % count], ring[index], ring[(index + 1) % count])
                if (b - c).length <= epsilon || abs(cross(b - a, c - b)) <= epsilon {
                    ring.remove(at: index)
                    changed = true
                } else {
                    index += 1
                }
            }
        }
        return ring.count >= 3 ? ring : []
    }

    /// The polygon's triangles, counter-clockwise, or none when they don't cover exactly its area. A vertex coinciding
    /// with a corner of the ear is a bridge's twin and doesn't block it; so doesn't a convex one touching the ear's edge
    /// (where the two sides of a bridge lie along each other); a reflex or flat one in or on the ear does.
    static func earClip(_ polygon: [Vector2]) -> [Vector2] {
        var ring = withoutFlatVertices(polygon)
        var triangles: [Vector2] = []
        while ring.count > 3 {
            guard let position = ring.indices.first(where: { isEar(ring, at: $0) }) else { return [] }
            let count = ring.count
            triangles += [ring[(position + count - 1) % count], ring[position], ring[(position + 1) % count]]
            ring.remove(at: position)
        }
        if ring.count == 3, cross(ring[1] - ring[0], ring[2] - ring[1]) > epsilon { triangles += ring }
        let covered = stride(from: 0, to: triangles.count, by: 3).reduce(0.0) {
            $0 + cross(triangles[$1 + 1] - triangles[$1], triangles[$1 + 2] - triangles[$1 + 1])
        }
        let whole = doubleArea(polygon)
        return abs(covered - whole) <= 1e-6 * max(1, abs(whole)) ? triangles : []
    }

    private static func isEar(_ ring: [Vector2], at position: Int) -> Bool {
        let count = ring.count
        let corners = [(position + count - 1) % count, position, (position + 1) % count]
        let (a, b, c) = (ring[corners[0]], ring[corners[1]], ring[corners[2]])
        guard cross(b - a, c - b) > epsilon else { return false }
        for other in ring.indices where !corners.contains(other) {
            let p = ring[other]
            if p == a || p == b || p == c { continue }
            let inside = cross(b - a, p - a) >= -epsilon && cross(c - b, p - b) >= -epsilon && cross(a - c, p - c) >= -epsilon
            if inside, cross(p - ring[(other + count - 1) % count], ring[(other + 1) % count] - p) <= epsilon { return false }
        }
        return true
    }
}
