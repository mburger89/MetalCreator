/// Triangles a check flagged, and what it says about them (implicit spec §2.2). The viewport tints them in the theme's warning role.
public struct MeshHighlight: Hashable, Sendable {
    /// Indices of the flagged triangles (triangle `t` is `triangles[3t ..< 3t + 3]`).
    public var triangles: [Int]
    public var label: String

    public init(triangles: [Int], label: String) {
        self.triangles = triangles
        self.label = label
    }
}
