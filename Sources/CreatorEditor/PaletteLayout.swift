import CreatorGeometry

/// The add-node palette's fixed size, computed so it can be placed inside the window before it is drawn
/// (`PalettePlacement`). It shows at most `visibleRows` matches; ↑/↓ scroll the rest into view, so the panel never
/// grows or jumps while the user types.
public enum PaletteLayout {
    /// The column inside the glass.
    public static let contentWidth = 220.0
    public static let fieldHeight = 28.0
    public static let rowHeight = 22.0
    public static let visibleRows = 10
    /// The line under the rows: "No matching nodes", or how many more matches are out of view.
    public static let captionHeight = 16.0
    /// Between the field, the rows and the caption.
    public static let spacing = 4.0
    /// The gap the palette keeps from the window's edges when it flips or is clamped.
    public static let windowMargin = 8.0

    /// The rows' height: `visibleRows` of them, filled or not.
    public static var rowsHeight: Double { Double(visibleRows) * rowHeight }

    /// The column's size inside the glass.
    public static var contentSize: Vector2 {
        Vector2(contentWidth, fieldHeight + spacing + rowsHeight + spacing + captionHeight)
    }

    /// The whole palette, glass included.
    public static var size: Vector2 {
        contentSize + Vector2(2 * GraphPanelLayout.glassPadding, 2 * GraphPanelLayout.glassPadding)
    }
}
