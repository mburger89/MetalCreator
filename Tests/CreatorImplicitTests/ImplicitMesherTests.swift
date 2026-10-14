import CreatorGeometry
import Synchronization
import Testing
@testable import CreatorImplicit

/// The mesher (implicit spec §4.3, §7): invariants on every mesh, volumes against the exact shapes, determinism.
struct ImplicitMesherTests {
    func mesher(_ solid: ImplicitSolid, bricks: Int = 4096) -> ImplicitMesher {
        ImplicitMesher(evaluator: CPUBatchEvaluator(solid), bricksPerBatch: bricks)
    }

    @Test func aSphereIsAClosedManifoldWithTheRightVolume() async throws {
        let solid = ImplicitSolid.sphere(radius: 10)
        let mesh = try await mesher(solid).mesh(solid, resolution: 0.5, quality: .export)
        let topology = MeshTopology(mesh)
        #expect(topology.isClosedManifold)
        #expect(topology.eulerCharacteristic == 2)
        let exact = 4.0 / 3 * Double.pi * 1000
        #expect(abs(mesh.signedVolume - exact) / exact < 0.005, "volume \(mesh.signedVolume) against \(exact)")
        let area = 4 * Double.pi * 100
        #expect(abs(mesh.surfaceArea - area) / area < 0.01)
        #expect(mesh.resolution == 0.5 && mesh.quality == .export && mesh.triangleCount > 1000)
    }

    @Test func theNewtonStepPutsVerticesOnTheSurfaceWithOutwardNormals() async throws {
        let solid = ImplicitSolid.sphere(radius: 10)
        let mesh = try await mesher(solid).mesh(solid, resolution: 0.5, quality: .preview)
        var worst: Float = 0
        var worstAlignment: Float = 1
        for (position, normal) in zip(mesh.positions, mesh.normals) {
            worst = max(worst, abs((position * position).sum().squareRoot() - 10))
            worstAlignment = min(worstAlignment, (position / (position * position).sum().squareRoot() * normal).sum())
        }
        #expect(worst < 0.01, "worst distance from the sphere \(worst)")
        #expect(worstAlignment > 0.999, "normals point away from the centre")
        let raw = try await mesher(solid).mesh(solid, resolution: 0.5, quality: .preview, snap: false)
        let rawWorst = raw.positions.map { abs(($0 * $0).sum().squareRoot() - 10) }.max() ?? 0
        #expect(worst < rawWorst, "snapping helps: \(worst) against \(rawWorst)")
        #expect(raw.normals.allSatisfy { $0 == .zero })
    }

    @Test func aRingHasAHoleThroughIt() async throws {
        let ring = ImplicitSolid.subtract([.cylinder(radius: 8, halfHeight: 3), .cylinder(radius: 4, halfHeight: 5)], blend: .constant(0))
        let mesh = try await mesher(ring).mesh(ring, resolution: 0.5, quality: .export)
        let topology = MeshTopology(mesh)
        #expect(topology.isClosedManifold)
        #expect(topology.eulerCharacteristic == 0, "a torus has Euler characteristic 0, not \(topology.eulerCharacteristic)")
        let exact = Double.pi * (64 - 16) * 6
        #expect(abs(mesh.signedVolume - exact) / exact < 0.02, "volume \(mesh.signedVolume) against \(exact)")
    }

    @Test func twoSeparatePiecesAreTwoSurfaces() async throws {
        let far = ImplicitSolid.moved(.sphere(radius: 3), RigidMove(origin: Vector3(12, 0, 0), xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ))
        let pair = ImplicitSolid.union([.sphere(radius: 3), far], blend: .constant(0))
        let mesh = try await mesher(pair).mesh(pair, resolution: 0.4, quality: .preview)
        let topology = MeshTopology(mesh)
        #expect(topology.isClosedManifold && topology.eulerCharacteristic == 4)
    }

    @Test func aSmoothBlendOfTwoBallsIsOneClosedSurface() async throws {
        let move = RigidMove(origin: Vector3(7, 0, 0), xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ)
        let moved = ImplicitSolid.moved(.sphere(radius: 5), move)
        let blend = ImplicitSolid.union([.sphere(radius: 5), moved], blend: .constant(4))
        let mesh = try await mesher(blend).mesh(blend, resolution: 0.4, quality: .preview)
        #expect(MeshTopology(mesh).isClosedManifold && MeshTopology(mesh).eulerCharacteristic == 2)
    }

    @Test func aMeshIsTheSameEveryTimeAndWhateverTheBatchSize() async throws {
        let solid = ImplicitFixtures.cylinder
        let first = try await mesher(solid).mesh(solid, resolution: 0.5, quality: .preview)
        let second = try await mesher(solid).mesh(solid, resolution: 0.5, quality: .preview)
        let small = try await mesher(solid, bricks: 7).mesh(solid, resolution: 0.5, quality: .preview)
        #expect(first.positions == second.positions && first.triangles == second.triangles)
        #expect(first.positions == small.positions && first.triangles == small.triangles)
    }

    @Test func nothingToMeshIsRefusedWithAMessage() async {
        let solid = ImplicitSolid.sphere(radius: 0.01)
        await #expect(throws: ImplicitMeshingError.empty) { try await mesher(solid).mesh(solid, resolution: 0.5, quality: .preview) }
    }

    @Test func progressRunsFromZeroToOne() async throws {
        let solid = ImplicitSolid.sphere(radius: 6)
        let seen = ProgressLog()
        _ = try await mesher(solid, bricks: 10).mesh(solid, resolution: 0.5, quality: .preview) { seen.append($0) }
        let values = seen.values
        #expect(values.first == 0 && values.last == 1)
        #expect(values == values.sorted() && values.count > 3)
    }

    @Test func anExportTooBigForMemoryIsRefusedBeforeItStarts() async throws {
        let solid = ImplicitSolid.sphere(radius: 10)
        let small = ImplicitMesher(evaluator: CPUBatchEvaluator(solid), budget: MeshingBudget(physicalMemory: 2_000_000))
        await #expect(throws: ImplicitMeshingError.self) { try await small.mesh(solid, resolution: 0.1, quality: .export) }
        // A preview is never refused: its passes are bounded by their coarse resolution.
        _ = try await small.mesh(solid, resolution: 1, quality: .preview)
    }

    @Test func cancellingFromTheProgressCallbackAfterTheFirstBatchStopsTheMesher() async {
        let solid = ImplicitSolid.sphere(radius: 6)
        let seen = ProgressLog()
        let task = Task {
            try await mesher(solid, bricks: 10).mesh(solid, resolution: 0.5, quality: .preview) { fraction in
                seen.append(fraction)
                // The first batch has been meshed: cancel this very task, so the check before the second batch must throw.
                if fraction > 0 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(seen.values.count == 2, "progress(0) and the first batch, then nothing: \(seen.values)")
    }
}

/// Collects progress values reported from the mesher.
final class ProgressLog: Sendable {
    private let stored = Mutex<[Double]>([])

    func append(_ value: Double) {
        stored.withLock { $0.append(value) }
    }

    var values: [Double] { stored.withLock { $0 } }
}
