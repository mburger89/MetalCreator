import CreatorGeometry
import Foundation

/// Dimensions are text and lines the host anchors in world space and the view draws over the part (ANSI practice). They
/// are no part of the scene: never in the GPU pass, the ID pass, framing or `sceneBounds`, and not in `renderKey`.
extension ViewportModel {
    /// The dimensions to draw, replacing the last. An equal list changes nothing.
    public func showDimensions(_ newDimensions: [OverlayDimension]) {
        if dimensions != newDimensions { dimensions = newDimensions }
    }

    /// The dimensions on screen, in list order (the last is on top). Empty while the camera animates (the element tree is
    /// not rebuilt per animation frame, gap M4-b) or the view has no size. Left out: a dimension that cannot be drawn
    /// (`DimensionLayout.place`). Records what it returns for `dimension(at:)`.
    public func placedDimensions(measuring measure: TextMeasure) -> [PlacedDimension] {
        let size = viewSize
        guard !size.isEmpty, !isAnimating else {
            drawnDimensions = []
            return []
        }
        let camera = DimensionCamera(pose: pose, size: size)
        let placed = dimensions.compactMap { DimensionLayout.place($0, style: dimensionStyle, camera: camera, measure: measure) }
        drawnDimensions = placed
        return placed
    }

    /// The dimension whose text box, as last drawn, contains `point`: the topmost (last drawn) first.
    public func dimension(at point: ScreenPoint) -> OverlayDimensionID? {
        drawnDimensions.last { $0.textContains(point) }?.id
    }
}
