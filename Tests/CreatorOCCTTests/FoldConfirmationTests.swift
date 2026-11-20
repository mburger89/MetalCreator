#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-5 R10: a flagged neighbour pair is confirmed by refining it; a steep spike turns its normal smoothly and is no fold.
struct FoldConfirmationTests {
    let tag = newTag()
    let kernel = OCCTKernel()

    @Test func aSteepSpikeIsNotAFold() async throws {
        let sheet = try await kernel.bsplineSheet(uCount: 9, vCount: 9, degree: 3, tag: tag)
        let net = try await kernel.controlNet(of: sheet).surface
        let spacing = (net.pole(5, 4) - net.pole(4, 4)).length
        let spiked = try await kernel.movingPoles(
            of: sheet, by: [PoleMove(index: PoleIndex(i: 4, j: 4), offset: Vector3(0, 0, 120 * spacing))])
        #expect(try await kernel.folds(spiked) == false)
    }

    /// The same needle one pole in from a corner: before R10 the neighbour comparison flagged it (the centre pole's does not reproduce).
    @Test func aSteepSpikeNearACornerIsNotAFold() async throws {
        let sheet = try await kernel.bsplineSheet(uCount: 9, vCount: 9, degree: 3, tag: tag)
        let net = try await kernel.controlNet(of: sheet).surface
        let spacing = (net.pole(5, 4) - net.pole(4, 4)).length
        let spiked = try await kernel.movingPoles(
            of: sheet, by: [PoleMove(index: PoleIndex(i: 1, j: 1), offset: Vector3(0, 0, 40 * spacing))])
        #expect(try await kernel.folds(spiked) == false)
    }

    @Test func aCornerDraggedAcrossStillFolds() async throws {
        let sheet = try await kernel.bsplineSheet(uCount: 3, vCount: 3, degree: 1, tag: tag)
        let folded = try await kernel.movingPoles(
            of: sheet, by: [PoleMove(index: PoleIndex(i: 0, j: 0), offset: Vector3(6, 6, 0))])
        #expect(try await kernel.folds(folded))
    }
}
#endif
