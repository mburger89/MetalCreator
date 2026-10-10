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
