import CreatorGeometry

/// Where a sketch's plane comes from (spec §3).
public enum SketchPlaneSource: Hashable, Sendable, Codable {
    /// A plane stored in the sketch itself.
    case fixed(Plane)
    /// The plane wired into the Sketch node's `plane` socket (resolved by the node in S4).
    case wired
}
