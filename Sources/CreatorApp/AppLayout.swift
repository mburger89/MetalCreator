import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorViewport
import MetalUI

/// The window's layout numbers (spec §6.1). The views are framed to them, so the model can tell the viewport
/// which part of it the floating panels cover (`modelArea`) without waiting for a layout. Where the graph panel really
/// is, is measured by the panel itself (`EditorModel.panelPlacement`).
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
    /// The space between the window buttons' right edge and the top bar's first control.
    public static let titleBarGap = 8.0

    /// The window's title-bar style (gap M6-c, MetalUI C8): hidden, so the glass top bar is drawn under the window
    /// buttons (spec §6.1). `MetalCreatorApp` and the tests' window both open with it.
    public static let windowStyle = WindowStyle.hiddenTitleBar

    /// The strip along the window's top that moves the window (gap M6-c, MetalUI C22): the margin above the top bar
    /// and the glass's padding, down to where the bar's controls start. Across it the whole width is a handle; below
    /// it only the bar's empty space is (`TopBar`), because a press that starts on a control must not move the window.
    public static let windowDragStripHeight = margin + GraphPanelLayout.glassPadding

    /// How far the top bar's content starts in from the glass's inner edge so that it clears the window buttons under
    /// a hidden title bar (gap M6-c): `titleBarInsets.left` is the buttons' right edge in the window, the glass starts
    /// at `margin` and pads its content by `GraphPanelLayout.glassPadding`. Zero in a standard window, whose
    /// insets are zero.
    public static func topBarClearance(titleBarInsets: Edges<Pixels>) -> Double {
        max(0, Double(titleBarInsets.left.value) + titleBarGap - margin - GraphPanelLayout.glassPadding)
    }

    /// Where "Show Producing Node" puts the node's top-left corner on the canvas, in canvas-local points.
    public static let revealPoint = Vector2(24, 24)

    /// The field legend's room (fields spec §6): it stands at the model area's lower left like the axis triad, one gap above it
    /// (the triad is 16 points from the model area's edges and 64 points square), so its left and bottom are the model
    /// area's plus those. The top and trailing insets are 0.
    public static func legendInsets(dock: DockSide, panelWidth: Double, panelHeight: Double) -> ViewportInsets {
        let area = modelArea(dock: dock, panelWidth: panelWidth, panelHeight: panelHeight)
        return ViewportInsets(top: 0, leading: area.leading + 16, bottom: area.bottom + 16 + TriadLayout().side + 12, trailing: 0)
    }

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
