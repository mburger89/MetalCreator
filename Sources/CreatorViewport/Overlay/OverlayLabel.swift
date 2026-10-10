import CreatorGeometry

/// A piece of text the host anchors in world space (a sketch dimension's value, sketcher spec §8). The viewport projects
/// the anchor with the camera every frame and draws the text over the surface in a small glass box
/// (`ViewportModel.overlayLabels()`). It never takes the pointer.
public struct OverlayLabel: Hashable, Sendable {
    /// How far (points) a label with a `nudge` sits from its anchor.
    public static let nudgeDistance = 16.0

    public var text: String
    /// The world point the label sits at.
    public var position: Vector3
    /// The role the text is coloured in (the theme's colour for that tint).
    public var tint: OverlayTint
    /// A world direction to move the label away along, `nudgeDistance` points, in whichever way that points on screen, so
    /// the box clears the geometry it names (a dimension's label stands off the line it measures). `nil`: centred on
    /// the anchor.
    public var nudge: Vector3?

    public init(_ text: String, at position: Vector3, tint: OverlayTint = .fullyConstrained, nudge: Vector3? = nil) {
        self.text = text
        self.position = position
        self.tint = tint
        self.nudge = nudge
    }
}
