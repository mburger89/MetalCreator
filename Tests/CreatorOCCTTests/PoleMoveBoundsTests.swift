#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-3 final review I2: only a preview's result takes the pole hull as its bounds.
struct PoleMoveBoundsTests {
    let tag = newTag()
    let kernel = OCCTKernel()

    func bump(previewing: Bool?) async throws -> Solid {
        let sheet = try await kernel.bsplineSheet(uCount: 30, vCount: 30, degree: 3, tag: tag)
        let moves = [PoleMove(index: PoleIndex(i: 15, j: 15), offset: Vector3(0, 0, 8))]
        guard let previewing else { return try await kernel.movingPoles(of: sheet, by: moves) }
        return try await kernel.movingPoles(of: sheet, by: moves, previewing: previewing)
    }

    @Test func aBigFaceKeepsTightBounds() async throws {
        for previewing in [nil, false] {
            let solid = try await bump(previewing: previewing)
            let mesh = try await kernel.tessellate(solid, tolerance: 0.01, angle: 0.2)
            let highest = mesh.positions.map(\.z).max() ?? 0
            #expect(solid.bounds.max.z >= highest - 1e-9)
            #expect(solid.bounds.max.z < highest + 0.05, "tight: a cubic bump over a 30 x 30 net is far below its pole")
        }
    }

    @Test func aPreviewUsesTheHull() async throws {
        let solid = try await bump(previewing: true)
        #expect(solid.bounds.max.z > 7.9 && solid.bounds.max.z <= 8.0 + 1e-3)
    }
}
#endif
