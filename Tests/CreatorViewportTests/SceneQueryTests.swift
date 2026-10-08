import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorViewport

@MainActor
struct SceneQueryTests {
    let bounds = BoundingBox(min: Vector3(-5, -10, 0), max: Vector3(5, 10, 30))

    @Test func meshesAreCachedPerSolidAndTolerance() async throws {
        let kernel = StubMeshKernel()
        let cache = TessellationCache()
        let a = try await fakeBox()
        let b = try await fakeBox(width: 4)
        try await cache.load([a, b], tolerance: 0.05, kernel: kernel)
        try await cache.load([a, b], tolerance: 0.05, kernel: kernel)
        #expect(await kernel.tessellations == 2)
        #expect(cache.tessellationCount == 2)
        let first = try #require(cache.mesh(for: a))
        try await cache.load([a], tolerance: 0.01, kernel: kernel)
        #expect(await kernel.tessellations == 3)
        #expect(cache.mesh(for: b) == nil, "a solid no longer shown is dropped")
        #expect(try #require(cache.mesh(for: a)).serial != first.serial, "a new tolerance is a new mesh")
    }

    @Test func aCancelledLoadLeavesTheCacheUntouched() async throws {
        let kernel = StubMeshKernel()
        let cache = TessellationCache()
        let kept = try await fakeBox()
        try await cache.load([kept], tolerance: 0.05, kernel: kernel)
        let other = try await fakeBox(width: 3)
        let task = Task { try await cache.load([other], tolerance: 0.05, kernel: kernel) }
        task.cancel()
        _ = await task.result
        #expect(cache.mesh(for: kept) != nil, "a superseded load must not prune")
        #expect(cache.mesh(for: other) == nil)
    }

    @Test func raysHitTheNearestFace() throws {
        let mesh = TestMeshes.box(bounds)
        // (2, 12) is off every quad's diagonal, so the hit doesn't depend on rounding at a shared triangle edge.
        let fromFront = Ray(origin: Vector3(2, -100, 12), direction: Vector3(0, 1, 0), minimumT: 0)
        let hit = try #require(MeshRaycast.nearest(fromFront, in: [(solidIndex: 4, mesh: mesh)]))
        #expect(hit.face == FaceID(2))
        #expect(hit.solidIndex == 4)
        #expect(isClose(hit.point, Vector3(2, -10, 12)))
        #expect(isClose(hit.distance, 90))
        let miss = Ray(origin: Vector3(50, -100, 15), direction: Vector3(0, 1, 0), minimumT: 0)
        #expect(MeshRaycast.nearest(miss, in: [(solidIndex: 0, mesh: mesh)]) == nil)
    }

    @Test func orthographicRaysCountWhatIsBehindTheirOrigin() throws {
        let mesh = TestMeshes.box(bounds)
        let inside = Ray(origin: Vector3(2, 0, 12), direction: Vector3(0, 1, 0), minimumT: -.infinity)
        #expect(try #require(MeshRaycast.nearest(inside, in: [(solidIndex: 0, mesh: mesh)])).face == FaceID(2))
        let perspective = Ray(origin: Vector3(2, 0, 12), direction: Vector3(0, 1, 0), minimumT: 0)
        #expect(try #require(MeshRaycast.nearest(perspective, in: [(solidIndex: 0, mesh: mesh)])).face == FaceID(4))
    }

    @Test func faceQueriesReadTheMesh() throws {
        let mesh = TestMeshes.box(bounds)
        let front = try #require(MeshQueries.faceBounds(mesh, FaceID(2)))
        #expect(front.min == Vector3(-5, -10, 0) && front.max == Vector3(5, -10, 30))
        #expect(isClose(try #require(MeshQueries.faceDirection(mesh, FaceID(2))), Vector3(0, -1, 0)))
        #expect(MeshQueries.faceDirection(mesh, FaceID(99)) == nil)
        #expect(MeshQueries.bounds(mesh) == bounds)
        let edges = try #require(MeshQueries.edgeBounds(mesh, [EdgeID(1), EdgeID(3)]))
        #expect(edges.min.z == 30 && edges.max.z == 30)
    }

    @Test func boundaryEdgesAndProducingNodesComeFromTheTopology() async throws {
        let node = NodeID()
        let box = try await fakeBox(node: node)
        #expect(MeshQueries.boundaryEdges(of: FaceID(2), in: box.topology).map(\.id.rawValue) == [0, 1, 8, 11])
        let face = try #require(box.topology.face(FaceID(2)))
        #expect(MeshQueries.producingNodes(of: face) == [node])
        let a = NodeID()
        let b = NodeID()
        let merged = FaceInfo(id: FaceID(0), kind: .plane, normal: .unitZ, area: 1, centroid: .zero,
                              tags: [TopoTag(node: b, item: 0, role: .endCap), TopoTag(node: a, item: 1, role: .endCap),
                                     TopoTag(node: a, item: 0, role: .endCap)])
        #expect(MeshQueries.producingNodes(of: merged) == [a, b].sorted())
    }

    @Test func boundaryEdgesSkipSeams() async throws {
        let rod = try await FakeKernel().extrude(.circle(radius: 2, center: .zero, plane: .xy), distance: 5, mode: .oneSided,
                                                 tag: NodeTag(node: NodeID(), item: 0))
        let side = try #require(rod.topology.faces.first { $0.kind == .cylinder })
        #expect(MeshQueries.boundaryEdges(of: side.id, in: rod.topology).allSatisfy { !$0.isSeam })
        #expect(MeshQueries.boundaryEdges(of: side.id, in: rod.topology).count == 2)
    }

    // MARK: - Handles

    /// Front, orthographic, 40 mm tall in a 200 × 200 view: 0.2 mm per point.
    let front = CameraPose(target: .zero, distance: 20 / tan(CameraPose.fieldOfView / 2), yaw: 0, pitch: 0,
                           projection: .orthographic)
    let size = ViewportSize(width: 200, height: 200)
    let upward = ViewportHandle(id: "extrude", anchor: .zero, direction: .unitZ, value: 10, range: 0.5...50,
                                style: .linear, tint: .solid)

    @Test func draggingAlongTheProjectedAxisChangesTheValue() {
        let value = HandleMath.value(for: upward, startValue: 10, from: ScreenPoint(100, 50),
                                     to: ScreenPoint(130, 0), pose: front, size: size)
        #expect(isClose(value, 20), "50 points up at 0.2 mm per point adds 10 mm; sideways motion is ignored")
    }

    @Test func handleValuesStayInRange() {
        #expect(HandleMath.value(for: upward, startValue: 10, from: ScreenPoint(100, 50), to: ScreenPoint(100, -5000),
                                 pose: front, size: size) == 50)
        #expect(HandleMath.value(for: upward, startValue: 10, from: ScreenPoint(100, 50), to: ScreenPoint(100, 5000),
                                 pose: front, size: size) == 0.5)
    }

    @Test func aHandleAlongTheViewAxisDoesNotJump() {
        let towardViewer = ViewportHandle(id: "depth", anchor: .zero, direction: Vector3(0, -1, 0), value: 10,
                                          range: 0...1000, style: .linear, tint: .solid)
        for target in [ScreenPoint(101, 50), ScreenPoint(100, 49), ScreenPoint(400, -300)] {
            #expect(HandleMath.value(for: towardViewer, startValue: 10, from: ScreenPoint(100, 50), to: target,
                                     pose: front, size: size) == 10)
        }
        let nearly = ViewportHandle(id: "tilted", anchor: .zero, direction: Vector3(0, -1, 0.01), value: 10,
                                    range: 0...1000, style: .linear, tint: .solid)
        #expect(HandleMath.value(for: nearly, startValue: 10, from: ScreenPoint(100, 50), to: ScreenPoint(100, 49),
                                 pose: front, size: size) == 10)
    }

    @Test func theNearestKnobWithinReachIsHit() {
        // The knob of `upward` is at (0, 0, 10): 50 points above the centre, at (100, 50).
        let lower = ViewportHandle(id: "lower", anchor: .zero, direction: .unitZ, value: 9, range: 0...50,
                                   style: .linear, tint: .feature)
        #expect(HandleMath.hit([lower, upward], at: ScreenPoint(102, 51), pose: front, size: size)?.id == "extrude")
        #expect(HandleMath.hit([upward], at: ScreenPoint(100, 70), pose: front, size: size) == nil)
        #expect(HandleMath.hit([upward], at: ScreenPoint(100, 50), pose: front, size: ViewportSize(width: 0, height: 0)) == nil)
    }
}
