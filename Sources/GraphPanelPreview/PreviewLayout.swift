import CreatorEditor
import CreatorGeometry
import CreatorGraph

/// The preview window's layout numbers. The window keeps one size, so the editor can be told where its panel is
/// (MetalUI has no geometry reader, docs/metalui-gaps.md M4-a, EP-a); `PreviewRoot` is framed to these.
enum PreviewLayout {
    static let window = Vector2(1280, 800)
    static let margin = 12.0
    static let leftPanelWidth = 380.0
    static let bottomPanelHeight = 300.0

    /// The graph panel's frame in the window for `dock`; `nil` while hidden.
    static func placement(_ dock: DockSide) -> PanelPlacement? {
        let panel: CanvasRect
        switch dock {
        case .left:
            panel = CanvasRect(origin: Vector2(margin, margin), size: Vector2(leftPanelWidth, window.y - 2 * margin))
        case .bottom:
            panel = CanvasRect(origin: Vector2(margin, window.y - margin - bottomPanelHeight),
                               size: Vector2(window.x - 2 * margin, bottomPanelHeight))
        case .hidden:
            return nil
        }
        return PanelPlacement(window: window, panel: panel)
    }
}
