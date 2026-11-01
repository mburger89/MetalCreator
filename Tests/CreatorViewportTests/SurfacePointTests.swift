import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

@MainActor
struct SurfacePointTests {
    let size = ViewportSize(width: 800, height: 600)

    private func shown(_ box: Solid) async -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), clock: ManualClock())
        model.viewSize = size
        model.show([ViewportItem(solid: box)])
        await model.waitForMeshes()
        return model
    }

    @Test func aRayThroughAMeshHitsItsNearSide() async throws {
        let box = try await fakeBox()
        let model = await shown(box)
        let centre = try #require(CameraMath.project(box.bounds.center, model.pose, size: size, sceneRadius: 20)).point
        let hit = try #require(model.surfacePoint(at: centre, solidIndex: 0))
        let onASide = [hit.x, hit.y, hit.z].enumerated().contains { index, value in
            let (low, high) = ([box.bounds.min.x, box.bounds.min.y, box.bounds.min.z][index],
                               [box.bounds.max.x, box.bounds.max.y, box.bounds.max.z][index])
            return abs(value - low) < 1e-6 || abs(value - high) < 1e-6
        }
        #expect(onASide)
        // The near side is nearer the eye than the centre is.
        let eye = model.pose.eye
        #expect((hit - eye).length < (box.bounds.center - eye).length)
    }

    @Test func aRayMissingTheItemIsNil() async throws {
        let model = await shown(try await fakeBox())
        #expect(model.surfacePoint(at: ScreenPoint(2, 2), solidIndex: 0) == nil)
        #expect(model.surfacePoint(at: ScreenPoint(400, 300), solidIndex: 5) == nil)
    }
}
