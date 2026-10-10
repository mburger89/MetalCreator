extension EditorModel {
    /// The pointer's shape over the canvas, or `nil` for the arrow: a closed hand while a middle-button drag pans it.
    /// MetalUI keeps a pressed element's style while the pointer leaves it, a middle button's drag included (`CI-H`
    /// item 6), so a fast pan keeps the hand. Moving
    /// nodes, wiring and box selection keep the arrow, and so does a canvas at rest: an open hand over empty canvas
    /// alone would need a hit test on every hover move.
    public var canvasCursor: CanvasCursor? {
        if case .panning? = interaction { return .grabbing }
        return nil
    }
}
