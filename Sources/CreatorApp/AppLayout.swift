import CreatorGeometry
import CreatorGraph
import CreatorViewport

/// The window's layout numbers (spec §6.1). The views are framed to them, so the model can tell the viewport
/// which part of it the floating panels cover without measuring anything (MetalUI has no geometry reader yet,
/// docs/metalui-gaps.md M4-a).
public enum AppLayout {
    /// Around the window's edge and between panels.
    public static let margin = 12.0
    public static let topBarHeight = 44.0
    /// The inspector's 280-point column plus its glass padding.
    public static let inspectorWidth = 300.0
    /// The "Show graph" button while the panel is hidden.
    public static let showButtonHeight = 44.0
    /// The graph panel's inner-edge resize handle.
    public static let resizeHandle = 8.0
    public static let defaultPanelWidth = 460.0
    public static let defaultPanelHeight = 300.0
    public static let panelWidths: ClosedRange<Double> = 240...900
    public static let panelHeights: ClosedRange<Double> = 160...700
    /// Where "Show Producing Node" puts the node's top-left corner on the canvas, in canvas-local points.
    public static let revealPoint = Vector2(24, 24)

    /// The part of the viewport the panels leave uncovered, for `ViewportModel.setModelArea(_:)`.
    public static func modelArea(dock: DockSide, panelWidth: Double, panelHeight: Double) -> ViewportInsets {
        let top = margin + topBarHeight
        let trailing = margin + inspectorWidth
        switch dock {
        case .left: return ViewportInsets(top: top, leading: margin + panelWidth + resizeHandle, bottom: 0, trailing: trailing)
        case .bottom: return ViewportInsets(top: top, leading: 0, bottom: margin + panelHeight + resizeHandle, trailing: trailing)
        case .hidden: return ViewportInsets(top: top, leading: 0, bottom: margin + showButtonHeight, trailing: trailing)
        }
    }
}
