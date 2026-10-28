import CreatorGeometry
import Foundation

/// Detects a solve that turns a corner or an arc of a sketch the other way (spec §7).
public enum SketchFlipCheck {
    /// What a refused edit says when the solve would flip the sketch; the one source for the sketch editor and the part's box.
    public static let refusal = "This value would flip the sketch."

    /// The sine below which a corner or an arc has no side (1°).
    public static let straightLimit: Double = sin(Double.pi / 180)

    /// Lengths under this have no direction.
    private static let degenerateLength = 1e-9

    /// True when a usable solve `after` turns a corner or an arc of `sketch` the other way from `before`.
    public static func isFlipped(_ before: SketchSolution, _ after: SketchSolution, in sketch: Sketch) -> Bool {
        guard after.status.isUsable else { return false }
        var lines: [(start: SketchEntityID, end: SketchEntityID)] = []
        for id in sketch.entityIDs {
            switch sketch.entities[id]?.kind {
            case .line(let start, let end):
                lines.append((start, end))
            case .arc(let center, let start, let end):
                if turned(sine(center, start, end, in: before), sine(center, start, end, in: after)) { return true }
            default:
                break
            }
        }
        for (i, first) in lines.enumerated() {
            for second in lines[(i + 1)...] {
                for shared in sharedPoints(first, second) {
                    let far1 = first.start == shared ? first.end : first.start
                    let far2 = second.start == shared ? second.end : second.start
                    if turned(sine(shared, far1, far2, in: before), sine(shared, far1, far2, in: after)) { return true }
                }
            }
        }
        return false
    }

    /// The endpoint entities two lines have in common, in the first line's order.
    private static func sharedPoints(_ a: (start: SketchEntityID, end: SketchEntityID),
                                     _ b: (start: SketchEntityID, end: SketchEntityID)) -> [SketchEntityID] {
        [a.start, a.end].filter { $0 == b.start || $0 == b.end }
    }

    /// The sine of the turn from `a − origin` to `b − origin`, or `nil` when a point is missing or a length is degenerate.
    private static func sine(_ origin: SketchEntityID, _ a: SketchEntityID, _ b: SketchEntityID,
                             in solution: SketchSolution) -> Double? {
        guard let o = solution.points[origin], let pa = solution.points[a], let pb = solution.points[b] else { return nil }
        let u = pa - o
        let v = pb - o
        let lengths = u.length * v.length
        guard u.length >= degenerateLength, v.length >= degenerateLength else { return nil }
        return (u.x * v.y - u.y * v.x) / lengths
    }

    /// True when both readings exist, both have a side, and the sides differ.
    private static func turned(_ before: Double?, _ after: Double?) -> Bool {
        guard let before, let after, abs(before) >= straightLimit, abs(after) >= straightLimit else { return false }
        return (before > 0) != (after > 0)
    }
}
