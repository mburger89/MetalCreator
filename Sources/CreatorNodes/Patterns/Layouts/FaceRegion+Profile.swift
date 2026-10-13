import CreatorGeometry
import Foundation

extension FaceRegion {
    /// The outline of a profile in its plane's own 2D coordinates: its outer loop and each hole as closed polylines, arcs cut
    /// into chords no more than `chordTolerance` from the arc, so Field Scatter reads a profile as it reads a face.
    static func outline(of profile: Profile2D) -> FaceRegion {
        FaceRegion(loops: profile.loops.map { loop in loop.flatMap { points(of: $0) } })
    }

    /// The points that stand for `segment`, from its start up to but not including its end: just the start for a line, chords
    /// for an arc (run from its `start` to its `end` angle, clockwise when `end < start`).
    private static func points(of segment: Segment2D) -> [Vector2] {
        switch segment {
        case .line(let start, _):
            return [start]
        case .arc(let center, let radius, let start, let end):
            let sweep = end.radians - start.radians
            let step = chordTolerance < radius ? 2 * acos(1 - chordTolerance / radius) : .pi
            let chords = min(max(Int((abs(sweep) / step).rounded(.up)), 1), 720)
            return (0..<chords).map { index in
                let angle = start.radians + sweep * Double(index) / Double(chords)
                return center + Vector2(cos(angle), sin(angle)) * radius
            }
        }
    }
}
