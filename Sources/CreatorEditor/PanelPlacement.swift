import CreatorGeometry
import CreatorGraph

/// Where the host lays the graph panel out in its window (MetalUI can't measure it: docs/metalui-gaps.md M4-a,
/// EP-a). `EditorModel.placement` asks for it when it needs window coordinates: to float the add-node palette over
/// the window, and to find the visible canvas's centre.
public struct PanelPlacement: Equatable, Sendable {
    /// The window's content size, in points.
    public var window: Vector2
    /// The panel's frame, in window points.
    public var panel: CanvasRect

    public init(window: Vector2, panel: CanvasRect) {
        self.window = window
        self.panel = panel
    }
}
