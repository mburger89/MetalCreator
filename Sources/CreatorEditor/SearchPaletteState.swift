import CreatorGeometry

/// The open add-node palette (spec §6.2: Tab or Space opens it at the cursor).
public struct SearchPaletteState: Equatable, Sendable {
    /// Where it opened, in canvas-local screen points. New nodes land under this point.
    public var screenPosition: Vector2
    /// The palette's top-left corner in window points (`PalettePlacement`), fixed while it is open. Without a host
    /// placement it is `screenPosition`.
    public var windowOrigin: Vector2
    public var query: String
    /// Index into the current matches of the entry Return adds.
    public var highlighted: Int
    /// Index of the first match shown: the palette shows `PaletteLayout.visibleRows` from here, keeping
    /// `highlighted` in view.
    public var firstVisible: Int

    public init(screenPosition: Vector2, windowOrigin: Vector2? = nil, query: String = "", highlighted: Int = 0,
                firstVisible: Int = 0) {
        self.screenPosition = screenPosition
        self.windowOrigin = windowOrigin ?? screenPosition
        self.query = query
        self.highlighted = highlighted
        self.firstVisible = firstVisible
    }
}
