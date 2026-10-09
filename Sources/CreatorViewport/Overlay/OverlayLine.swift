import CreatorGeometry

/// One straight overlay segment in world space (a sketch line, or one piece of a tessellated arc).
public struct OverlayLine: Hashable, Sendable {
    public var a: Vector3
    public var b: Vector3
    public var tint: OverlayTint
    /// Width in points.
    public var width: Double
    /// Drawn as dashes of `OverlayGeometry.dash` points with `OverlayGeometry.gap`-point gaps (construction).
    public var isDashed: Bool

    public init(_ a: Vector3, _ b: Vector3, tint: OverlayTint, width: Double = 1.5, isDashed: Bool = false) {
        self.a = a
        self.b = b
        self.tint = tint
        self.width = width
        self.isDashed = isDashed
    }
}
