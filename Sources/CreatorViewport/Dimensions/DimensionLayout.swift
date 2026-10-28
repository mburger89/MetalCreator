/// Turns a world-space dimension into what is drawn on screen.
enum DimensionLayout {
    /// The placed dimension, or `nil` when it cannot be drawn: no length, a point behind the camera, a plane seen too
    /// nearly edge-on (`DimensionStyle.edgeOnLimit`), or anything not finite.
    @MainActor
    static func place(_ dimension: OverlayDimension, style: DimensionStyle, camera: DimensionCamera,
                      measure: TextMeasure) -> PlacedDimension? {
        switch dimension.geometry {
        case .linear:
            placeLinear(dimension, style: style, camera: camera, measure: measure)
        case .radial:
            placeRadial(dimension, style: style, camera: camera, measure: measure)
        case .angular:
            placeAngular(dimension, style: style, camera: camera, measure: measure)
        }
    }
}
