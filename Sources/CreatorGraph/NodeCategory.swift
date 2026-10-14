/// Drives a node's header colour and palette grouping (spec §6.6).
public enum NodeCategory: String, Sendable, Codable, CaseIterable {
    case value, profile, solid, selection, feature
    /// Patterns: Place, Points to Placements and the feature shortcuts built on them.
    case patterns
    /// Lists & Trees: the nodes that reshape, pick from and describe nested lists. Before `output`, which stays last.
    case lists
    /// Fields (fields spec §3): values that vary over space, the maths that combines them and the nodes that sample them.
    /// After Lists & Trees, before `output`.
    case fields
    /// Implicit solids (implicit spec §3): signed distance functions, the nodes that make, combine and shell them. After
    /// Fields, before `output`.
    case implicit
    /// Meshes (implicit spec §3.6): the Mesh node, and in later sub-projects the mesh tools and checks. After Implicit.
    case mesh
    case output

    /// The name the node library shows: "Value", "Lists & Trees".
    public var title: String {
        switch self {
        case .lists: "Lists & Trees"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}
