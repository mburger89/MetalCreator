import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// The open-shell face set of a cached mesh is made when the mesh is cached, not on every frame.
@MainActor
struct OpenShellCacheTests {
    @Test func aCachedMeshKnowsItsOpenShellFaces() async throws {
        let mesh = SheetFixtures.sheet(facingEye: true)
        let topology = Topology(
            faces: [FaceInfo(id: FaceID(0), kind: .plane, normal: nil, area: 1, centroid: .zero, tags: [], isOnOpenShell: true)],
            edges: [])
        let solid = Solid(topology: topology, bounds: BoundingBox(min: .zero, max: Vector3(1, 1, 1)), storage: DisplayMeshStorage(mesh))
        let cache = TessellationCache()
        try await cache.load([solid], tolerance: 0.1, kernel: FakeKernel())
        #expect(cache.mesh(for: solid)?.openShellFaces == [FaceID(0)])
    }
}
