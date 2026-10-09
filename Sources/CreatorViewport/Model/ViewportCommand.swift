import CreatorGeometry

/// The viewport's commands, from keys, the view cube's buttons and its View menu (spec §6.3).
public enum ViewportCommand: Hashable, Sendable {
    /// Frame the selection, or everything when nothing is selected.
    case frame
    case zoomIn
    case zoomOut
    /// Go to the document's home view (isometric and framed when none is set).
    case home
    /// Make the current view the home view.
    case setHome
    /// Look at a view-cube region.
    case view(ViewCubeRegion)
    case rotate(CubeArrow)
    case projection(Projection)
    case shading(ShadingMode)
}

extension ViewportCommand {
    /// Whether the command can change the camera's orientation or projection (refused while navigation is planar).
    var turnsTheCamera: Bool {
        switch self {
        case .view, .rotate, .home, .projection: true
        case .frame, .zoomIn, .zoomOut, .setHome, .shading: false
        }
    }
}
