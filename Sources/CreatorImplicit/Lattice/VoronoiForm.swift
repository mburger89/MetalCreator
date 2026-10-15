/// Which part of the Voronoi diagram of the seeds is solid (implicit spec §3.4).
public enum VoronoiForm: Int, Hashable, Sendable, CaseIterable {
    /// The cell edges, where three or more cells meet: a network of struts whose diameter is the thickness.
    case struts = 0
    /// The cell walls, where two cells meet: a closed-cell foam whose walls are as thick as the thickness.
    case foam = 1

    /// The names the node's segmented control shows, in raw-value order.
    public static let options = ["Struts", "Foam"]

    public var name: String { Self.options[rawValue] }
}
