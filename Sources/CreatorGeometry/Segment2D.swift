import Foundation

/// One piece of a profile loop, in plane coordinates.
public enum Segment2D: Hashable, Sendable {
    case line(Vector2, Vector2)
    /// An arc from `start` to `end`: counter-clockwise when `end > start` (`end - start` of 2π is a full
    /// circle), clockwise when `end < start`. A clockwise arc is how a counter-clockwise loop runs
    /// along a notch cut into it (sketcher spec §5 step 5, S4).
    case arc(center: Vector2, radius: Double, start: Angle, end: Angle)

    public var startPoint: Vector2 {
        switch self {
        case .line(let a, _): a
        case .arc(let c, let r, let start, _): c + Vector2(cos(start.radians), sin(start.radians)) * r
        }
    }

    public var endPoint: Vector2 {
        switch self {
        case .line(_, let b): b
        case .arc(let c, let r, _, let end): c + Vector2(cos(end.radians), sin(end.radians)) * r
        }
    }

    public var length: Double {
        switch self {
        case .line(let a, let b): (b - a).length
        case .arc(_, let r, let start, let end): r * abs(end.radians - start.radians)
        }
    }

    /// Points whose bounding box contains the segment (conservative for arcs).
    public var boundingPoints: [Vector2] {
        switch self {
        case .line(let a, let b): [a, b]
        case .arc(let c, let r, _, _): [c + Vector2(-r, -r), c + Vector2(r, r)]
        }
    }
}
