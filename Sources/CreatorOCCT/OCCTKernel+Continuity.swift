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

extension OCCTKernel {
    /// The continuity of a sheet's free edge against a face of another body (`occt_edge_continuity_against`, NS-2).
    public func continuity(of edge: EdgeID, in first: Solid, against face: FaceID, of second: Solid) throws -> EdgeContinuity {
        try Task.checkCancellation()
        guard edge.rawValue >= 0, edge.rawValue < first.topology.edges.count,
              face.rawValue >= 0, face.rawValue < second.topology.faces.count else {
            throw KernelError.invalidInput("That edge or face no longer exists.")
        }
        let source = try shape(of: first), target = try shape(of: second)
        do {
            // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure. Revert once fixed.
            return try Self.serialized { () throws -> EdgeContinuity in
                try source.continuity(edgeIndex: edge.rawValue + 1, against: target, faceIndex: face.rawValue + 1)
            }
        } catch let error as OCCTError {
            if error.message.hasPrefix("occt: ") { throw KernelError.occt("continuity", error) }
            throw KernelError.invalidInput(error.message)
        }
    }
}

extension OCCTShape {
    /// `occt_edge_continuity_against` for the edge at 1-based `edgeIndex` and `other`'s face at `faceIndex`. Call under `OCCTKernel.serialized`.
    func continuity(edgeIndex: Int, against other: OCCTShape, faceIndex: Int) throws(OCCTError) -> EdgeContinuity {
        var raw = occt_edge_continuity()
        try Self.check { status in
            occt_edge_continuity_against(self.raw, Int32(edgeIndex), other.raw, Int32(faceIndex), &raw, status)
        }
        return EdgeContinuity(positionGap: raw.position_gap, angleGap: raw.angle_gap, curvatureGap: raw.curvature_gap,
                              absoluteCurvatureGap: raw.absolute_curvature_gap)
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
