import CreatorGeometry

/// A pinch over the canvas under way: the transform it zooms from and its centre in canvas-local screen points.
struct CanvasPinch: Equatable {
    var transform: CanvasTransform
    var centre: Vector2
}
