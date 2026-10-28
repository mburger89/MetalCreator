import CreatorGeometry
import Foundation

/// Dimensions are text and lines the host anchors in world space and the view draws over the part (ANSI practice). They
/// are no part of the scene: never in the GPU pass, the ID pass, framing or `sceneBounds`, and not in `renderKey`.
extension ViewportModel {
    /// The dimensions to draw, replacing the last. An equal list changes nothing.
    public func showDimensions(_ newDimensions: [OverlayDimension]) {
        if dimensions != newDimensions { dimensions = newDimensions }
        // A box whose dimension is gone (the sketch is done, an undo, a solve that dropped it) closes with no commit.
        if let box = valueBox, !newDimensions.contains(where: { $0.id == box.id }) { closeBox(.cancelled) }
    }

    /// The dimensions on screen, in list order (the last is on top). Empty while the camera animates (the element tree is
    /// not rebuilt per animation frame, gap M4-b) or the view has no size. Left out: a dimension that cannot be drawn
    /// (`DimensionLayout.place`); labels that would overlap stack apart (`DimensionDeclutter`). Records what it returns for `dimension(at:)`.
    public func placedDimensions(measuring measure: TextMeasure) -> [PlacedDimension] {
        let size = viewSize
        guard !size.isEmpty, !isAnimating else {
            drawnDimensions = []
            return []
        }
        let camera = DimensionCamera(pose: pose, size: size)
        var placed = DimensionDeclutter.place(dimensions, style: dimensionStyle, camera: camera, measure: measure)
        // The edited dimension's text is under its value box: kept for the box to sit on, not drawn.
        if let edited = valueBox?.id, let index = placed.firstIndex(where: { $0.id == edited }) {
            valueBoxAnchor = ValueBoxAnchor(origin: placed[index].textOrigin, size: placed[index].textSize)
            placed[index].showsText = false
        }
        drawnDimensions = placed
        return placed
    }

    /// The dimension whose text box, as last drawn, contains `point`: the topmost (last drawn) first.
    public func dimension(at point: ScreenPoint) -> OverlayDimensionID? {
        drawnDimensions.last { $0.textContains(point) }?.id
    }
}
