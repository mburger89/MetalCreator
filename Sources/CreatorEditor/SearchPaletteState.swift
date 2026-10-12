import CreatorGeometry

/// The open add-node palette (spec §6.2: Tab or Space opens it at the cursor).
public struct SearchPaletteState: Equatable, Sendable {
    /// Where it opened, in canvas-local screen points. New nodes land under this point.
    public var screenPosition: Vector2
    /// Where it opened, in window points: the point `SearchPaletteOverlay` anchors the palette's top-left corner at
    /// (MetalUI flips it to the point's left or above it, and clamps it, at the window's edges). Fixed while it is open.
    /// Without a hovered window point and a placed panel it is `screenPosition`.
    public var windowPoint: Vector2
    public var query: String
    /// Index into the current matches of the entry Return adds.
    public var highlighted: Int
    /// Index of the first match shown: the palette shows `PaletteLayout.visibleRows` from here, keeping
    /// `highlighted` in view.
    public var firstVisible: Int

    public init(screenPosition: Vector2, windowPoint: Vector2? = nil, query: String = "", highlighted: Int = 0,
                firstVisible: Int = 0) {
        self.screenPosition = screenPosition
        self.windowPoint = windowPoint ?? screenPosition
        self.query = query
        self.highlighted = highlighted
        self.firstVisible = firstVisible
    }
}
