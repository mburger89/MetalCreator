/// How the viewport projects the scene (spec §6.3).
public enum Projection: String, Sendable, Codable, CaseIterable {
    case perspective
    case orthographic
}
