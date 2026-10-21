import CreatorKernel

/// The solid a To Implicit bake was made from, and the tolerance it was tessellated at: what lets a lattice's Face mapping know which
/// solid its region came from (implicit spec §3.5). Equal by identity of the solid, like the blocks.
public final class BakeSource: Hashable, Sendable {
    public let solid: Solid
    public let tolerance: Double

    public init(solid: Solid, tolerance: Double) {
        self.solid = solid
        self.tolerance = tolerance
    }

    public static func == (lhs: BakeSource, rhs: BakeSource) -> Bool { lhs.solid === rhs.solid && lhs.tolerance == rhs.tolerance }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(solid))
        hasher.combine(tolerance)
    }
}
