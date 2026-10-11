/// Drives a node's header colour and palette grouping (spec §6.6).
public enum NodeCategory: String, Sendable, Codable, CaseIterable {
    case value, profile, solid, selection, feature
    /// Patterns: Place, Points to Placements and the feature shortcuts built on them.
    case patterns
    /// Lists & Trees: the nodes that reshape, pick from and describe nested lists. Before `output`, which stays last.
    case lists
    case output

    /// The name the node library shows: "Value", "Lists & Trees".
    public var title: String {
        switch self {
        case .lists: "Lists & Trees"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}
