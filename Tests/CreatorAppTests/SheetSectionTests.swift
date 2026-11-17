import CreatorGeometry
import CreatorKernel
import CreatorViewport
import Testing
@testable import CreatorApp

private final class EmptyStorage: SolidStorage {
    let estimatedBytes = 0
}

/// NS-1 Task 9 (ruling R4): an open body is outlined but never capped, and its missing cap is no failure.
@MainActor
struct SheetSectionTests {
    @Test func aSheetGetsNoCapAndNoProblem() async throws {
        let sheet = Solid(
            topology: Topology(
                faces: [FaceInfo(id: FaceID(0), kind: .plane, normal: nil, area: 1, centroid: .zero, tags: [], isOnOpenShell: true)],
                edges: [EdgeInfo(id: EdgeID(0), kind: .line, direction: nil, length: 1, midpoint: .zero, convexity: .unknown,
                                 faces: [FaceID(0)]),
                ]),
            bounds: BoundingBox(min: Vector3(-5, -5, -5), max: Vector3(5, 5, 5)), storage: EmptyStorage())
        let model = SectionCapModel(kernel: FakeKernel(), tolerance: 0.05)
        model.follow(clip: ViewportClip(origin: Vector3(0, 0, 1), normal: .unitZ), items: [ViewportItem(solid: sheet)])
        await model.waitForCaps()
        #expect(model.section == nil && model.problem == nil)
    }
}
