import COCCT
import CreatorGeometry
import CreatorKernel

/// Matching a sheet's open edge to another body's edge (NURBS spec NS-4, R9).
extension OCCTShape {
    /// The shape with face `faceIndex` and its edge `edge` (0-based) matched to `target`'s edge `targetEdge`.
    /// Call under `OCCTKernel.serialized`.
    func matchingFace(_ faceIndex: Int, edge: Int, to target: OCCTShape, targetEdge: Int,
                      continuity: Int) throws(OCCTError) -> OCCTShape {
        try Self.make { status in
            occt_match_face(self.raw, Int32(faceIndex + 1), Int32(edge + 1), target.raw, Int32(targetEdge + 1), Int32(continuity), status)
        }
    }
}

extension OCCTKernel {
    public func matched(_ sheet: Solid, edge: EdgeID, to target: EdgeID, of body: Solid,
                        continuity: PatchContinuity) async throws -> Solid {
        try Task.checkCancellation()
        guard sheet.hasOpenShell else { throw KernelError.invalidInput("Match Surface takes a sheet; this is a closed solid.") }
        let faceCount = sheet.topology.faces.count
        guard faceCount == 1 else {
            throw KernelError.invalidInput(
                "Match Surface changes a sheet with one face; this one has \(faceCount.formatted(.number.locale(.messages))).")
        }
        guard (0..<sheet.topology.edges.count).contains(edge.rawValue),
              (0..<body.topology.edges.count).contains(target.rawValue) else {
            throw KernelError.invalidInput("That edge no longer exists.")
        }
        let source = try shape(of: sheet)
        let other = try shape(of: body)
        guard source !== other else { throw KernelError.invalidInput("The target edge must be on another body.") }
        let grade = continuity == .g0 ? 0 : continuity == .g1 ? 1 : 2
        let result: OCCTShape
        do {
            // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure.
            result = try Self.serialized { () throws -> OCCTShape in
                try source.matchingFace(0, edge: edge.rawValue, to: other, targetEdge: target.rawValue, continuity: grade)
            }
        } catch let error as OCCTError {
            if error.message.hasPrefix("occt: ") { throw KernelError.occt("match surface", error) }
            throw KernelError.invalidInput(Self.writingNumbers(in: error.message))
        }
        try Task.checkCancellation()
        return try carryingTopology(of: result, from: sheet, source: source, operation: "match surface")
    }
}
