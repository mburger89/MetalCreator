import CreatorGeometry

/// Filled triangles in world space, drawn under the overlay's lines (a sketch region's faint fill, sketcher spec §8).
/// Fills never take the pointer: they are not in the ID pass.
public struct OverlayFill: Hashable, Sendable {
    /// Three points per triangle, in either winding; a trailing one or two are ignored.
    public var vertices: [Vector3]
    public var tint: OverlayTint

    public init(vertices: [Vector3], tint: OverlayTint = .region) {
        self.vertices = vertices
        self.tint = tint
    }

    public var triangleCount: Int { vertices.count / 3 }
}
