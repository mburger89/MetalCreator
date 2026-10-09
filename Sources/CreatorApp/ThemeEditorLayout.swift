import CreatorGraph

/// The theme editor's layout numbers. It floats at the window's top-right corner, below the top bar, over the
/// inspector, and runs down to the window's bottom margin, or to just above the graph panel when that is docked at
/// the bottom, so the panel stays whole.
enum ThemeEditorLayout {
    /// The editor's content column, inside its glass padding.
    static let width = 340.0
    /// The panel's distance from the window's top edge: below the top bar.
    static let top = AppLayout.margin * 2 + AppLayout.topBarHeight
    /// A role's row.
    static let rowHeight = 24.0
    /// A role's swatch.
    static let swatchWidth = 40.0
    static let swatchHeight = 18.0
    /// Between the editor's sections.
    static let spacing = 8.0

    /// The panel's distance from the window's bottom edge: a margin, or, over a graph panel docked at the bottom, a
    /// margin above that panel's resize handle (`AppLayout.graphPanelFrame`, `PanelArea`).
    static func bottom(dock: DockSide, panelHeight: Double) -> Double {
        switch dock {
        case .bottom: AppLayout.margin + panelHeight + AppLayout.resizeHandle + AppLayout.margin
        case .left, .hidden: AppLayout.margin
        }
    }
}
