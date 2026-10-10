import CreatorEditor
import CreatorGeometry

extension AppModel {
    /// Where the graph panel is in the window, from `AppLayout`'s numbers and the window's size; `nil` before the
    /// viewport's first draw (the window's size is the viewport's, gap M4-a) or while the panel is hidden. Observed:
    /// a resize rebuilds what reads it (the canvas's culling) one task after the viewport's draw records the size.
    public var panelPlacement: PanelPlacement? {
        let size = viewport.observedViewSize
        return panelPlacement(inWindowOf: Vector2(size.width, size.height))
    }

    /// Where the graph panel is in a `window`-sized window.
    public func panelPlacement(inWindowOf window: Vector2) -> PanelPlacement? {
        guard window.isFinite, window.x >= 1, window.y >= 1,
              let panel = AppLayout.graphPanelFrame(dock: editor.dock, panelWidth: panelWidth, panelHeight: panelHeight,
                                                    window: window) else { return nil }
        return PanelPlacement(window: window, panel: panel)
    }
}
