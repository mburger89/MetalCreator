/// Which part of a triply periodic minimal surface is solid (implicit spec §3.4).
public enum TPMSForm: Int, Hashable, Sendable, CaseIterable {
    /// A wall of `thickness` on the surface, separating two volumes.
    case sheet = 0
    /// One of the two volumes: solid where the surface function is below the level, which `thickness` offsets.
    case network = 1

    /// The names the node's segmented control shows, in raw-value order.
    public static let options = ["Sheet", "Network"]

    public var name: String { Self.options[rawValue] }
}
