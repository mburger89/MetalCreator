/// Whether the material angle across an edge is under 180° (convex), over (concave), or flat (smooth).
public enum Convexity: String, Sendable, Codable {
    case convex, concave, smooth, unknown
}
