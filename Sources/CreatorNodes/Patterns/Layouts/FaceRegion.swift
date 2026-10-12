import CreatorGeometry
import Foundation

/// The outline of a flat face in the face's own 2D coordinates (Face Pattern, patterns spec §3): its outer loop and each hole as
/// closed polylines (arcs cut into chords no more than `chordTolerance` from the arc). A point is in the face by the even-odd
/// rule over all the loops, so a hole needs no special case.
struct FaceRegion {
    /// How far a chord may lie from the arc it stands for, in millimetres.
    static let chordTolerance = 0.01

    /// Closed loops, the last point not repeating the first.
    let loops: [[Vector2]]

    init(loops: [[Vector2]]) {
        self.loops = loops.filter { $0.count >= 3 }
    }

    /// The corners of the box round every loop; `nil` for a face with no outline.
    var bounds: (min: Vector2, max: Vector2)? {
        let points = loops.joined()
        guard let first = points.first else { return nil }
        return points.reduce((first, first)) { box, p in
            (Vector2(Swift.min(box.0.x, p.x), Swift.min(box.0.y, p.y)), Vector2(Swift.max(box.1.x, p.x), Swift.max(box.1.y, p.y)))
        }
    }

    /// Whether `point` is on the face: inside an odd number of loops.
    func contains(_ point: Vector2) -> Bool {
        var inside = false
        for loop in loops {
            var previous = loop[loop.count - 1]
            for current in loop {
                if (current.y > point.y) != (previous.y > point.y),
                   point.x < (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x {
                    inside.toggle()
                }
                previous = current
            }
        }
        return inside
    }

    /// The distance from `point` to the nearest edge of any loop.
    func distanceToBoundary(_ point: Vector2) -> Double {
        var nearest = Double.infinity
        for loop in loops {
            var previous = loop[loop.count - 1]
            for current in loop {
                nearest = Swift.min(nearest, Self.distance(from: point, toSegment: previous, current))
                previous = current
            }
        }
        return nearest
    }

    /// Whether a placement may stand at `point`: on the face and at least `margin` from every edge, holes' included.
    func allows(_ point: Vector2, margin: Double) -> Bool {
        contains(point) && (margin <= 0 || distanceToBoundary(point) >= margin - 1e-9)
    }

    private static func distance(from p: Vector2, toSegment a: Vector2, _ b: Vector2) -> Double {
        let along = b - a
        let lengthSquared = along.x * along.x + along.y * along.y
        guard lengthSquared > 0 else { return (p - a).length }
        let t = Swift.min(Swift.max(((p.x - a.x) * along.x + (p.y - a.y) * along.y) / lengthSquared, 0), 1)
        return (p - (a + along * t)).length
    }

    /// The edge of the area placements may stand in, for the viewport: each loop moved `margin` into the face, corners
    /// mitred (and the mitre held to four margins, so a sharp corner doesn't fly off). Exact on straight edges; at an arc or a
    /// sharp corner only a guide, since placements are kept clear of the edge by distance, not by this outline.
    func insetOutline(margin: Double) -> [[Vector2]] {
        guard margin > 0 else { return loops }
        return loops.enumerated().map { index, loop in
            let area = Self.signedArea(loop)
            // A loop inside an odd number of others is a hole: the face lies outside it. Counter-clockwise puts the inside on the left.
            let enclosing = loops.indices.filter { $0 != index && Self.contains(loops[$0], loop[0]) }.count
            let faceSide = (enclosing.isMultiple(of: 2) ? 1.0 : -1.0) * (area >= 0 ? 1.0 : -1.0)
            return Self.mitred(loop, by: margin * faceSide)
        }
    }

    private static func signedArea(_ loop: [Vector2]) -> Double {
        var sum = 0.0
        var previous = loop[loop.count - 1]
        for current in loop {
            sum += previous.x * current.y - current.x * previous.y
            previous = current
        }
        return sum / 2
    }

    private static func contains(_ loop: [Vector2], _ point: Vector2) -> Bool {
        FaceRegion(loops: [loop]).contains(point)
    }

    /// `loop` moved by `offset` along the left normal of each edge (negative: the right), corners where the moved edges meet.
    private static func mitred(_ loop: [Vector2], by offset: Double) -> [Vector2] {
        let count = loop.count
        let edges = (0..<count).map { index -> (point: Vector2, direction: Vector2)? in
            let delta = loop[(index + 1) % count] - loop[index]
            let length = delta.length
            guard length > 1e-12 else { return nil }
            let direction = delta * (1 / length)
            return (loop[index] + Vector2(-direction.y, direction.x) * offset, direction)
        }
        return (0..<count).map { index in
            let corner = loop[index]
            guard let before = edges[(index + count - 1) % count], let after = edges[index] else { return corner }
            let cross = before.direction.x * after.direction.y - before.direction.y * after.direction.x
            guard abs(cross) > 1e-9 else { return corner + (after.point - loop[index]) }
            // Where the line through `before` meets the line through `after`.
            let gap = after.point - before.point
            let t = (gap.x * after.direction.y - gap.y * after.direction.x) / cross
            let meeting = before.point + before.direction * t
            let shift = meeting - corner
            return shift.length > 4 * abs(offset) ? corner + shift * (4 * abs(offset) / shift.length) : meeting
        }
    }
}
