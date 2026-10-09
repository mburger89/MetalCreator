import CreatorGeometry

/// What the renderer's overlay buffer is built from: the overlay, and the camera and scale its dashes and plane
/// grid depend on.
struct OverlayBufferKey: Equatable {
    var overlay: ViewportOverlay
    var pose: CameraPose
    var size: ViewportSize
    var gridSpacing: Double
    var scale: Float
    var palette: ViewportPalette
}
