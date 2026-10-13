import CreatorGeometry

extension EditorModel {
    /// The smallest pinch magnification the zoom follows. MetalUI's magnification is 1 plus the pinch's deltas, so
    /// a hard pinch-in can reach zero or below.
    public static let minimumMagnification = 0.05

    /// A trackpad pinch over the canvas (spec §6.2, docs/metalui-gaps.md M5-f), from MetalUI's `MagnifyGesture`:
    /// `magnification` is cumulative from 1 since the pinch began, and `centre` is where it began, in canvas-local
    /// screen points (the pointer doesn't move during a pinch). The canvas zooms by `magnification` from the
    /// transform it had when the pinch began, about `centre`, within `CanvasTransform.zoomRange`; a pinch-in to zero
    /// or below holds at `minimumMagnification` rather than springing back, and a non-finite value changes nothing.
    /// The pinch's first change closes the add-node palette, which adds at the point it opened over. A pinch MetalUI drops
    /// without an end (a new pinch replaces it, or the window stops being key) arrives as `pinchEnded()` through the
    /// gesture's `onCancelled` (C16, docs/metalui-gaps.md VI-a), so the next one starts from the canvas as it is. A
    /// pinch while a press drags on the canvas changes nothing (as a scroll then doesn't).
    public func pinchChanged(magnification: Double, centre: Vector2) {
        guard interaction == nil, magnification.isFinite, centre.isFinite else { return }
        if pinchStart == nil {
            palette = nil
            pinchStart = CanvasPinch(transform: transform, centre: centre)
        }
        guard let start = pinchStart else { return }
        let zoomed = start.transform.zoomed(by: max(magnification, Self.minimumMagnification), around: centre)
        if zoomed != transform { transform = zoomed }
    }

    /// The pinch ended, or MetalUI dropped it (`onCancelled`): the next one zooms from wherever this one left the canvas.
    public func pinchEnded() {
        pinchStart = nil
    }
}
