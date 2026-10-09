import CreatorGeometry

/// A pinch over the canvas under way: the transform it zooms from, its centre in canvas-local screen points, and the
/// transform its last change left, so a pinch that lost its end can tell that something else moved the canvas since.
struct CanvasPinch: Equatable {
    var transform: CanvasTransform
    var centre: Vector2
    var applied: CanvasTransform
}
