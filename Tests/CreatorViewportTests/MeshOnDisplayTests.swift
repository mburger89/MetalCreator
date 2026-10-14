import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorViewport

/// A mesh the host built is drawn as it is (implicit spec §5.1): the kernel is never asked to tessellate it.
@MainActor
struct MeshOnDisplayTests {
    let mesh = DisplayMesh(
        positions: [Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(0, 3, 0), Vector3(0, 0, 2)],
        normals: [Vector3](repeating: .unitZ, count: 4), indices: [0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3],
        triangleFaces: [FaceID](repeating: FaceID(0), count: 4), edgePolylines: [:])

    @Test func theCacheKeepsAMeshOnDisplayWithoutTheKernel() async throws {
        let kernel = StubMeshKernel()
        let cache = TessellationCache()
        let shown = Solid(displaying: mesh)
        try await cache.load([shown], tolerance: 0.05, kernel: kernel)
        #expect(await kernel.tessellations == 0 && cache.tessellationCount == 0)
        #expect(cache.mesh(for: shown)?.mesh.indices == mesh.indices)
    }

    @Test func aSceneWithAMeshAndAPartLoadsBoth() async throws {
        let kernel = StubMeshKernel()
        let model = ViewportModel(kernel: kernel, pose: nil)
        model.viewSize = ViewportSize(width: 400, height: 300)
        let part = try await fakeBox()
        let shown = Solid(displaying: mesh)
        model.show([ViewportItem(solid: part), ViewportItem(solid: shown)])
        await model.waitForMeshes()
        #expect(model.items.count == 2 && model.meshError == nil)
        #expect(await kernel.tessellations == 1, "only the part")
        #expect(model.displayMesh(of: shown)?.positions == mesh.positions)
        #expect(model.sceneBounds?.max.x == max(4, part.bounds.max.x))
    }

    @Test func hoveringAMeshWithNoFacesDoesNotTrouble() async throws {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: nil)
        model.viewSize = ViewportSize(width: 400, height: 300)
        model.show([ViewportItem(solid: Solid(displaying: mesh))])
        await model.waitForMeshes()
        for x in stride(from: 50.0, to: 350.0, by: 50) {
            model.pointerHovered(at: ScreenPoint(x, 150))
        }
        #expect(model.meshError == nil)
    }
}
