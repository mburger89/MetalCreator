import CreatorGeometry
import CreatorGraph

/// Where the graph panel is in its window, measured by the panel itself (`GraphPanel`'s `onGeometryChange` reads its
/// frame in the window's space and the window's size from the environment; docs/metalui-gaps.md M4-a, EP-a).
/// `EditorModel.panelPlacement` holds it for what needs window coordinates: the canvas's frame (a library drop, the
/// visible centre, the culling).
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
