#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-2 review fix: R2 comes before the G2 limits on interior points and curves.
extension BoundaryPatchG2Tests {
    @Test func g2WithInteriorPointsOnASheetEdgeIsRefused() async throws {
        let (part, edges) = try await squareHole()
        let wording = "A G2 patch can't pass through interior points or curves."
        await #expect {
            try await kernel.boundaryPatch(PatchBoundary(curves: [], edges: edges, part: part), interior: [Vector3(5, 5, 1)],
                                           interior: [], continuity: .g2, tag: tag)
        } throws: { message(of: $0) == wording }
        let ridge = try await line(Vector3(3, 5, 0.5), Vector3(7, 5, 0.5))
        await #expect {
            try await kernel.boundaryPatch(PatchBoundary(curves: [], edges: edges, part: part), interior: [], interior: [ridge],
                                           continuity: .g2, tag: tag)
        } throws: { message(of: $0) == wording }
    }

    @Test func g2WithInteriorPointsAndNoSheetPieceIsHeldAtG0() async throws {
        // R2 first: no piece lies on a sheet, so the request is only G0 (and G0 takes interior points and curves).
        let square = try await unitSquare()
        let warning = "No bounding edge is a sheet's open edge, so the patch is only G0."
        let dimple = try await kernel.boundaryPatch(PatchBoundary(curves: square, edges: [], part: nil),
                                                    interior: [Vector3(5, 5, 1)], interior: [], continuity: .g2, tag: tag)
        #expect(dimple.warnings == [warning])
        let ridge = try await line(Vector3(3, 5, 0.5), Vector3(7, 5, 0.5))
        let ridged = try await kernel.boundaryPatch(PatchBoundary(curves: square, edges: [], part: nil),
                                                    interior: [], interior: [ridge], continuity: .g2, tag: tag)
        #expect(ridged.warnings == [warning])
    }
}
#endif
