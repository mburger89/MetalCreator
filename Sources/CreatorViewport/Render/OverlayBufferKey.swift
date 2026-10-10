import CreatorGeometry

/// What the renderer's overlay buffer is built from: the overlay, the scale and palette, and from the camera only what
/// the instances depend on, so an orbit or a pan inside a grid cell doesn't rebuild them.
struct OverlayBufferKey: Equatable {
    var overlay: ViewportOverlay
    /// Where the plane grid is centred and how far it reaches; `nil` without a grid plane.
    var grid: OverlayGeometry.GridExtent?
    /// The millimetres a point covers, which dashes are cut at; `nil` when no line is dashed.
    var dashZoom: Double?
    var scale: Float
    var palette: ViewportPalette
}
