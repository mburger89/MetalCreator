import CreatorGeometry

/// The open add-node palette (spec §6.2: Tab or Space opens it at the cursor).
public struct SearchPaletteState: Equatable, Sendable {
    /// Where it opened, in canvas-local screen points. New nodes land under this point.
    public var screenPosition: Vector2
    public var query: String
    /// Index into the current matches of the entry Return adds.
    public var highlighted: Int

    public init(screenPosition: Vector2, query: String = "", highlighted: Int = 0) {
        self.screenPosition = screenPosition
        self.query = query
        self.highlighted = highlighted
    }
}
