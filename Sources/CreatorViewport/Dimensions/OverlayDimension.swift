import CreatorGeometry

/// A dimension the host asks the viewport to draw: world-space geometry and the text to show. The viewport places it
/// on screen every frame (`DimensionLayout`), and it never reaches the GPU pass, framing or `sceneBounds`.
public struct OverlayDimension: Hashable, Sendable {
    public var id: OverlayDimensionID
    public var geometry: DimensionGeometry
    public var text: String
    /// `.dimensionDriving`, `.dimensionReference`, `.conflicting` or `.selected`.
    public var tint: OverlayTint
    /// Draws the pin mark beside the text.
    public var isPinned: Bool
    /// Drawn faded.
    public var isGhosted: Bool

    public init(id: OverlayDimensionID, geometry: DimensionGeometry, text: String, tint: OverlayTint = .dimensionDriving,
                isPinned: Bool = false, isGhosted: Bool = false) {
        self.id = id
        self.geometry = geometry
        self.text = text
        self.tint = tint
        self.isPinned = isPinned
        self.isGhosted = isGhosted
    }
}
