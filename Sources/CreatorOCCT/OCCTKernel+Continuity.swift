import COCCT
import CreatorGeometry
import CreatorKernel

extension OCCTKernel {
    /// The continuity of the two faces along an edge (`occt_edge_continuity_of`, G-b).
    public func continuity(along edge: EdgeID, of solid: Solid) throws -> EdgeContinuity {
        try Task.checkCancellation()
        guard edge.rawValue >= 0, edge.rawValue < solid.topology.edges.count else {
            throw KernelError.invalidInput("That edge no longer exists.")
        }
        let info = solid.topology.edges[edge.rawValue]
        guard !info.isSeam, info.faces.count == 2, info.faces[0] != info.faces[1] else {
            throw KernelError.unsupported("continuity of a seam")
        }
        let source = try shape(of: solid)
        do {
            // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure. Revert once fixed.
            return try Self.serialized { () throws -> EdgeContinuity in try source.continuity(edgeIndex: edge.rawValue + 1) }
        } catch let error as OCCTError {
            throw KernelError.occt("continuity", error)
        }
    }
}

extension OCCTShape {
    /// `occt_edge_continuity_of` for the edge at 1-based `edgeIndex`. Call under `OCCTKernel.serialized`.
    func continuity(edgeIndex: Int) throws(OCCTError) -> EdgeContinuity {
        var raw = occt_edge_continuity()
        try Self.check { status in occt_edge_continuity_of(self.raw, Int32(edgeIndex), &raw, status) }
        return EdgeContinuity(positionGap: raw.position_gap, angleGap: raw.angle_gap, curvatureGap: raw.curvature_gap,
                              absoluteCurvatureGap: raw.absolute_curvature_gap)
    }
}
