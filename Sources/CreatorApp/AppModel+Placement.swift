import CreatorEditor
import CreatorGeometry

extension AppModel {
    /// Where the graph panel is in the window, from `AppLayout`'s numbers and the window's size; `nil` before the
    /// viewport's first draw (the window's size is the viewport's, gap M4-a) or while the panel is hidden.
    public var panelPlacement: PanelPlacement? {
        panelPlacement(inWindowOf: Vector2(viewport.viewSize.width, viewport.viewSize.height))
    }

    /// Where the graph panel is in a `window`-sized window.
    public func panelPlacement(inWindowOf window: Vector2) -> PanelPlacement? {
        guard window.isFinite, window.x >= 1, window.y >= 1,
              let panel = AppLayout.graphPanelFrame(dock: editor.dock, panelWidth: panelWidth, panelHeight: panelHeight,
                                                    window: window) else { return nil }
        return PanelPlacement(window: window, panel: panel)
    }
}
