/// What a drawing tool has placed so far (`SketchEditorModel`'s in-progress stroke).
enum DrawState: Hashable, Sendable {
    case idle
    /// A line's start; after each line the chain goes on from its end.
    case lineFrom(SketchAnchor)
    case circleAround(SketchAnchor)
    case arcAround(SketchAnchor)
    case arcFrom(center: SketchAnchor, start: SketchAnchor)
}
