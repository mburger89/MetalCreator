import CreatorGeometry
import CreatorSketch

/// The constraint a line's end infers from its start (sketcher spec §8): horizontal when the end is within the
/// tolerance of the start's height, else vertical when it's within it of the start's x. The end is snapped onto it.
enum LineInference: Hashable, Sendable {
    case horizontal
    case vertical

    /// The inference for a line from `start` to `end`, and the end it snaps to; none when ⌘ suppresses it.
    static func infer(from start: Vector2, to end: Vector2, tolerance: Double, suppressed: Bool) -> (LineInference?, Vector2) {
        guard !suppressed, (end - start).length > tolerance else { return (nil, end) }
        if abs(end.y - start.y) <= tolerance { return (.horizontal, Vector2(end.x, start.y)) }
        if abs(end.x - start.x) <= tolerance { return (.vertical, Vector2(start.x, end.y)) }
        return (nil, end)
    }

    func constraint(on line: SketchEntityID) -> SketchConstraint {
        switch self {
        case .horizontal: .horizontal(line)
        case .vertical: .vertical(line)
        }
    }
}
