import CreatorGeometry
import CreatorGraph
import CreatorImplicit

extension Field {
    /// The box the field's interesting values lie in, when that is known (implicit spec §3.1: Isosurface takes its bounds "from the
    /// field's support when known"). Only an implicit solid read as a field has one: its surface's box, which a level inside
    /// ±`level` of the surface stays within once grown by it. Everything else (distances, gradients, noise, pictures) goes on forever.
    func support(level: Double) -> BoundingBox? {
        guard case .implicit(let reference) = self else { return nil }
        return ImplicitSolid.grown(reference.payload.payloadBounds, by: abs(level))
    }
}
