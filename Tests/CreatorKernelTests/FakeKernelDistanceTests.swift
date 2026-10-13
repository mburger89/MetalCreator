import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// Fields spec §3.1 and §8: `Kernel.distances` on the Fake. A 10 mm cube stands on z = 0, centred on x and y.
struct FakeKernelDistanceTests {
    let tag = NodeTag(node: NodeID(), item: 0)

    func cube(_ kernel: FakeKernel) async throws -> Solid {
        try await kernel.extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided, tag: tag)
    }

    /// A solid whose faces are written by hand: a Fake prism's faces carry no positions.
    func solid(faces: [FaceInfo]) -> Solid {
        Solid(topology: Topology(faces: faces, edges: []), bounds: BoundingBox(min: .zero, max: Vector3(1, 1, 1)), storage: FakeStorage())
    }

    func face(_ id: Int, kind: SurfaceKind = .plane, normal: Vector3?, at centroid: Vector3) -> FaceInfo {
        FaceInfo(id: FaceID(id), kind: kind, normal: normal, area: 1, centroid: centroid, tags: [])
    }

    // MARK: solids

    @Test func aCubesSignedDistanceIsMinusFiveAtItsCentreAndZeroOnAFace() async throws {
        let kernel = FakeKernel()
        let solid = try await cube(kernel)
        let found = try await kernel.distances(from: [Vector3(0, 0, 5), Vector3(5, 0, 5), Vector3(0, 0, 10), Vector3(0, -5, 2)],
                                               to: .solid(solid), signed: true)
        #expect(found == [-5, 0, 0, 0])
    }

    @Test func outsideTheCubeTheDistanceIsPositiveAndExact() async throws {
        let kernel = FakeKernel()
        let solid = try await cube(kernel)
        let found = try await kernel.distances(from: [Vector3(8, 0, 5), Vector3(8, 8, 5), Vector3(8, 8, 13), Vector3(0, 0, -2)],
                                               to: .solid(solid), signed: true)
        #expect(found[0] == 3)
        #expect(abs(found[1] - 18.0.squareRoot()) < 1e-12, "past an edge it is the distance to the edge")
        #expect(abs(found[2] - 27.0.squareRoot()) < 1e-12, "past a corner it is the distance to the corner")
        #expect(found[3] == 2)
    }

    @Test func unsignedIsTheDistanceToTheSurfaceWhicheverSideThePointIsOn() async throws {
        let kernel = FakeKernel()
        let solid = try await cube(kernel)
        let found = try await kernel.distances(from: [Vector3(0, 0, 5), Vector3(1, 0, 5), Vector3(8, 0, 5)],
                                               to: .solid(solid), signed: false)
        #expect(found == [5, 4, 3])
    }

    @Test func aBatchGivesExactlyWhatEachPointGivesOnItsOwn() async throws {
        let kernel = FakeKernel()
        let solid = try await cube(kernel)
        let points = (0..<50).map { Vector3(Double($0) * 0.7 - 12, Double($0 % 7) - 3, Double($0 % 11) * 1.3 - 1) }
        let batch = try await kernel.distances(from: points, to: .solid(solid), signed: true)
        for (index, point) in points.enumerated() {
            let single = try await kernel.distances(from: [point], to: .solid(solid), signed: true)
            #expect(single == [batch[index]])
        }
    }

    // MARK: edges

    @Test func anEdgesDistanceAtAKnownPointIsExact() async throws {
        let kernel = FakeKernel()
        let solid = try await cube(kernel)
        // Edge 0 is the first segment's edge on the start cap: (-5,-5,0) to (5,-5,0).
        let found = try await kernel.distances(from: [Vector3(0, -8, 4), Vector3(9, -5, 0), Vector3(0, -5, 0)],
                                               to: .edges(EdgeSet(solid: solid, edges: [EdgeID(0)])), signed: true)
        #expect(found == [5, 4, 0], "perpendicular to the edge, past its end, and on it; signed is ignored for edges")
    }

    @Test func severalEdgesGiveTheNearest() async throws {
        let kernel = FakeKernel()
        let solid = try await cube(kernel)
        let both = EdgeSet(solid: solid, edges: [EdgeID(0), EdgeID(1)])  // the start cap's and the end cap's edge of segment 0
        let found = try await kernel.distances(from: [Vector3(0, -5, 8), Vector3(0, -5, 3)], to: .edges(both), signed: false)
        #expect(found == [2, 3])
    }

    @Test func anEdgeThatIsNotStraightOrCircularIsNotSupported() async throws {
        let kernel = FakeKernel()
        var topology = try await cube(kernel).topology
        topology.edges[0].curve = nil
        let bare = Solid(topology: topology, bounds: BoundingBox(min: .zero, max: Vector3(1, 1, 1)), storage: FakeStorage())
        await #expect(throws: KernelError.unsupported("distance to an edge that isn't straight or circular")) {
            try await kernel.distances(from: [.zero], to: .edges(EdgeSet(solid: bare, edges: [EdgeID(0)])), signed: false)
        }
    }

    // MARK: faces

    @Test func aPlanarFaceIsMeasuredToItsPlane() async throws {
        let kernel = FakeKernel()
        let plate = solid(faces: [face(0, normal: -.unitZ, at: .zero), face(1, normal: .unitZ, at: Vector3(0, 0, 6))])
        let found = try await kernel.distances(from: [Vector3(1, 2, 3), Vector3(1, 2, -4)],
                                               to: .faces(FaceSet(solid: plate, faces: [FaceID(1)])), signed: true)
        #expect(found == [3, 10])
        let nearest = try await kernel.distances(from: [Vector3(1, 2, 2)], to: .faces(FaceSet(solid: plate, faces: [FaceID(0), FaceID(1)])),
                                                 signed: false)
        #expect(nearest == [2])
    }

    @Test func aCurvedFaceIsNotSupported() async throws {
        let kernel = FakeKernel()
        let round = solid(faces: [face(0, kind: .cylinder, normal: .unitZ, at: .zero)])
        await #expect(throws: KernelError.unsupported("distance to a curved face")) {
            try await kernel.distances(from: [.zero], to: .faces(FaceSet(solid: round, faces: [FaceID(0)])), signed: false)
        }
    }

    // MARK: refusals and the contract

    @Test func anEmptySelectionAndAMissingIDAreRefused() async throws {
        let kernel = FakeKernel()
        let solid = try await cube(kernel)
        await #expect(throws: KernelError.invalidInput("No edges are selected to measure to.")) {
            try await kernel.distances(from: [.zero], to: .edges(EdgeSet(solid: solid, edges: [])), signed: false)
        }
        await #expect(throws: KernelError.invalidInput("No faces are selected to measure to.")) {
            try await kernel.distances(from: [.zero], to: .faces(FaceSet(solid: solid, faces: [])), signed: false)
        }
        await #expect(throws: KernelError.invalidInput("A selected edge doesn't exist on the solid.")) {
            try await kernel.distances(from: [.zero], to: .edges(EdgeSet(solid: solid, edges: [EdgeID(999)])), signed: false)
        }
        await #expect(throws: KernelError.invalidInput("A selected face doesn't exist on the solid.")) {
            try await kernel.distances(from: [.zero], to: .faces(FaceSet(solid: solid, faces: [FaceID(-1)])), signed: false)
        }
    }

    @Test func noPointsGiveNoDistances() async throws {
        let kernel = FakeKernel()
        let solid = try await cube(kernel)
        #expect(try await kernel.distances(from: [], to: .solid(solid), signed: true).isEmpty)
    }

    @Test func eachCallIsLogged() async throws {
        let kernel = FakeKernel()
        let solid = try await cube(kernel)
        await kernel.clearLog()
        _ = try await kernel.distances(from: [.zero], to: .solid(solid), signed: true)
        _ = try await kernel.distances(from: [.zero], to: .solid(solid), signed: true)
        #expect(await kernel.operationLog == ["distances", "distances"])
    }

    @Test func aCancelledCallIsSkipped() async throws {
        let kernel = FakeKernel()
        let solid = try await cube(kernel)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await kernel.distances(from: [.zero], to: .solid(solid), signed: true)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
