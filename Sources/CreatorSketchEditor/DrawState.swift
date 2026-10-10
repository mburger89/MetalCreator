/// What a drawing tool has placed so far (`SketchEditorModel`'s in-progress stroke).
enum DrawState: Hashable, Sendable {
    case idle
    /// A line's start; after each line the chain goes on from its end.
    case lineFrom(SketchAnchor)
    case circleAround(SketchAnchor)
    case arcAround(SketchAnchor)
    case arcFrom(center: SketchAnchor, start: SketchAnchor)
    /// A 3-point arc's start, then its start and end.
    case arcThroughFrom(SketchAnchor)
    case arcThrough(start: SketchAnchor, end: SketchAnchor)
}

extension DrawState {
    /// Whether the next click may be held on a curve under it (point-on, sketcher spec §8). A circle's radius point and
    /// a centre arc's end are only sizes and keep no point, so a curve under them must not move them: they would snap
    /// with no constraint and no glyph (`SketchEditorModel.inferredConstraints` infers nothing there).
    var snapsToCurves: Bool {
        switch self {
        case .circleAround, .arcFrom: false
        case .idle, .lineFrom, .arcAround, .arcThroughFrom, .arcThrough: true
        }
    }
}
