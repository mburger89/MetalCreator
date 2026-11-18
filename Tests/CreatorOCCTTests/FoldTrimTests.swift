#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-3 Task 9 review: the fold query still classifies a trimmed face by its trim.
struct FoldTrimTests {
    let tag = newTag()
    let kernel = OCCTKernel()

    @Test func aTrimmedFaceStillClassifies() async throws {
        let circle = try await kernel.makeCurve([
            .arc(center: .zero, normal: .unitZ, radius: 10, start: Vector3(10, 0, 0), sweep: 2 * .pi),
        ], tag: tag)
        let plane = try await kernel.planarSurface([circle], tag: tag)
        let sheet = try await kernel.rebuilt(plane, as: RebuildSpec(degreeU: 3, degreeV: 3, spansU: 12, spansV: 12)).sheet
        #expect(try await kernel.folds(sheet) == false)
        let net = try await kernel.controlNet(of: sheet).surface
        let corner = net.pole(0, 0)
        let centre = net.pole(net.uCount / 2, net.vCount / 2)
        #expect(corner.length > 12 && centre.length < 2, "the corner is outside the trim, the middle inside")
        let outside = try await kernel.movingPoles(
            of: sheet, by: [PoleMove(index: PoleIndex(i: 0, j: 0), offset: Vector3(60, 60, 0))])
        #expect(try await kernel.folds(outside) == false, "a fold outside the trim is not on the face")
        let inside = try await kernel.movingPoles(
            of: sheet, by: [PoleMove(index: PoleIndex(i: net.uCount / 2, j: net.vCount / 2), offset: Vector3(60, 60, 0))])
        #expect(try await kernel.folds(inside))
    }
}
#endif
