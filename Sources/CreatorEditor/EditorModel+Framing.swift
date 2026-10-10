import CreatorGeometry

extension EditorModel {
    /// Screen points kept clear around what F frames (MetalNodes §18.6).
    public static let framingPadding = 40.0

    /// F with the pointer over the canvas (spec 2026-10-09 §3): pans and zooms so the selection fills the visible
    /// canvas (`visibleCanvasSize`) inside `framingPadding`, centred, the zoom within `CanvasTransform.zoomRange`.
    /// With nothing selected (or only nodes no longer on the canvas) it frames everything, as the viewport's F does.
    /// Returns false for an empty canvas, so the key goes on.
    @discardableResult
    public func frameSelection() -> Bool {
        guard let bounds = bounds(of: canvasSelection) ?? bounds(of: allItems) else { return false }
        transform = .framing(bounds, in: visibleCanvasSize, padding: Self.framingPadding)
        return true
    }
}
