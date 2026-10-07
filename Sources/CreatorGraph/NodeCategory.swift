/// Drives a node's header colour and palette grouping (spec §6.6).
public enum NodeCategory: String, Sendable, Codable, CaseIterable {
    case value, profile, solid, selection, feature, output
}
