import CreatorGeometry

/// One overlay knob in world space: a square `size` points wide (a sketch point).
public struct OverlayPoint: Hashable, Sendable {
    public var position: Vector3
    public var tint: OverlayTint
    public var size: Double

    public init(_ position: Vector3, tint: OverlayTint, size: Double = 6) {
        self.position = position
        self.tint = tint
        self.size = size
    }
}
