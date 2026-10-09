import CreatorGeometry

/// Everything a redraw depends on. `ViewportView` passes it as the `MetalView`'s `value:`, because an on-demand
/// MetalUI surface redraws only when its value changes (`MV-A` item 4).
public struct ViewportRenderKey: Hashable, Sendable {
    var pose: CameraPose
    var isAnimating: Bool
    var shading: ShadingMode
    var hovered: PickTarget?
    var hoveredCubeRegion: ViewCubeRegion?
    var sceneGeneration: Int
    var handles: [ViewportHandle]
    var cube: ViewCubeLayout
    /// The triad's place: a model area that moves only the triad (a bottom dock's resize) redraws it.
    var triad: TriadLayout
    /// The theme's GPU colours: switching themes redraws.
    var palette: ViewportPalette
    /// The host's overlay: a sketch edit redraws.
    var overlay: ViewportOverlay
}
