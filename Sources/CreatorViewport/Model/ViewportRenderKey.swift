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
}
