import CreatorGeometry

/// Everything one viewport frame draws: a snapshot made by `ViewportModel.frame(at:)`, so the renderer never
/// reads observable state.
struct ViewportFrame {
    var pose: CameraPose
    var size: ViewportSize
    var sceneBounds: BoundingBox?
    var items: [FrameItem]
    var shading: ShadingMode
    var gridSpacing: Double
    var handles: [ViewportHandle]
    var cube: ViewCubeLayout
    var hoveredCubeRegion: ViewCubeRegion?
    var triad: TriadLayout
    /// The colours to draw in: the model's theme (`ViewportModel.palette`).
    var palette: ViewportPalette = .dracula
    /// The host's overlay (`ViewportModel.overlay`): the sketch editor's geometry and plane grid.
    var overlay = ViewportOverlay()
    /// Whether the view cube is drawn (`ViewportModel.showsViewCube`: not while navigation is planar).
    var showsViewCube = true

    /// Half the scene's diagonal (at least 1 mm), used for depth ranges.
    var sceneRadius: Double { sceneBounds.map { max($0.size.length / 2, 1) } ?? 1 }

    var pickKey: PickKey {
        PickKey(pose: pose, size: size, items: items.flatMap { [$0.meshSerial, $0.solidIndex] })
    }
}
