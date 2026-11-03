import CreatorGeometry
import Foundation
import Testing
@testable import CreatorKernel

/// The loft end conditions' kernel API (G-d Task 2): the types, the checks every kernel makes, and the fake kernel's refusal.
struct LoftEndTests {
    let tag = NodeTag(node: NodeID(), item: 0)
    let square = Profile2D.rectangle(width: 6, height: 6, plane: Plane.xy.offset(by: 20))

    func part() async throws -> (FakeKernel, Solid, FaceID) {
        let kernel = FakeKernel()
        let solid = try await kernel.extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided, tag: tag)
        let top = try #require(solid.topology.faces.first { $0.kind == .plane && $0.normal == Vector3(0, 0, 1) })
        return (kernel, solid, top.id)
    }

    /// A loft through `sections` with the given ends, on the fake kernel.
    func loft(
        _ kernel: FakeKernel, _ sections: [Profile2D]? = nil, ruled: Bool = false, part: Solid?, start: LoftEnd? = nil, end: LoftEnd? = nil
    ) async throws -> Solid {
        try await kernel.loft(sections ?? [square], ruled: ruled, part: part, start: start, end: end, tag: tag)
    }

    @Test func aLoftEndHasADefaultWeightOfOne() {
        let end = LoftEnd(face: FaceID(3), continuity: .curvature)
        #expect(end.weight == 1)
        #expect(LoftContinuity.allCases.map(\.rawValue) == [0, 1, 2])
    }

    @Test func theOldSignatureForwardsWithNoEnds() async throws {
        let kernel = FakeKernel()
        await #expect(throws: KernelError.unsupported("loft")) {
            try await kernel.loft([square, square], ruled: false, tag: tag)
        }
        #expect(await kernel.operationLog == ["loft"])
    }

    @Test func aFaceEndIsRefusedByTheFakeKernel() async throws {
        let (kernel, solid, top) = try await part()
        await #expect(throws: KernelError.unsupported("loft end conditions")) {
            try await loft(kernel, part: solid, start: LoftEnd(face: top, continuity: .tangent))
        }
        await #expect(throws: KernelError.unsupported("loft end conditions")) {
            try await loft(kernel, part: solid, end: LoftEnd(face: top, continuity: .free))
        }
    }

    @Test func aRuledLoftTakesNoEndCondition() async throws {
        let (kernel, solid, top) = try await part()
        for continuity in LoftContinuity.allCases {
            await #expect(throws: KernelError.invalidInput("Straight sides can't have end conditions.")) {
                try await loft(kernel, ruled: true, part: solid, start: LoftEnd(face: top, continuity: continuity))
            }
        }
        #expect(KernelError.ruledLoftEnds.userMessage == "Straight sides can't have end conditions.")
    }

    @Test func aFaceEndNeedsAPart() async throws {
        let kernel = FakeKernel()
        let face = LoftEnd(face: FaceID(0), continuity: .tangent)
        await #expect(throws: KernelError.invalidInput("Pick a face of the part for the loft's start.")) {
            try await loft(kernel, part: nil, start: face)
        }
        await #expect(throws: KernelError.invalidInput("Pick a face of the part for the loft's end.")) {
            try await loft(kernel, part: nil, end: face)
        }
    }

    @Test func aVanishedFaceIsNamed() async throws {
        let (kernel, solid, _) = try await part()
        await #expect(throws: KernelError.invalidInput("That face no longer exists.")) {
            try await loft(kernel, part: solid, start: LoftEnd(face: FaceID(99), continuity: .tangent))
        }
    }

    @Test func aWeightMustBePositiveWhereThereIsACondition() async throws {
        let (kernel, solid, top) = try await part()
        for weight in [0, -1, Double.nan, .infinity] {
            await #expect(throws: KernelError.weightNotPositive) {
                try await loft(kernel, part: solid, start: LoftEnd(face: top, continuity: .curvature, weight: weight))
            }
        }
        // Free ignores the weight (and this kernel then refuses the face end on its own account).
        await #expect(throws: KernelError.unsupported("loft end conditions")) {
            try await loft(kernel, part: solid, start: LoftEnd(face: top, continuity: .free, weight: 0))
        }
    }

    @Test func aLoftNeedsTwoSectionsInAll() async throws {
        let (kernel, solid, top) = try await part()
        let face = LoftEnd(face: top, continuity: .tangent)
        await #expect(throws: KernelError.invalidInput("A loft needs at least two sections.")) {
            try await loft(kernel, [], part: solid, start: face)
        }
        // A face at each end needs no profile.
        await #expect(throws: KernelError.unsupported("loft end conditions")) {
            try await loft(kernel, [], part: solid, start: face, end: face)
        }
    }

    @Test func theLoftSentencesReadAsTheSpecSays() {
        #expect(KernelError.loftCannotMeetTangent.userMessage == "The loft can't meet the part tangent (G1) here.")
        #expect(KernelError.loftCannotMeetCurvature.userMessage == "The loft can't meet the part with matching curvature (G2) here.")
        #expect(KernelError.loftWeightTooLarge.userMessage == "The tangency weight is too large for this loft.")
        #expect(KernelError.loftEndFaceNotFlat.userMessage == "The loft's end face must be flat.")
        #expect(KernelError.loftShimSentences.contains(KernelError.loftWeightTooLarge.userMessage))
    }
}
