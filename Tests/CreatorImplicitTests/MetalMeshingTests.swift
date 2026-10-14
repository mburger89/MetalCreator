#if canImport(Metal)
import CreatorGeometry
import Synchronization
import Testing
@testable import CreatorImplicit

/// Meshing on the Metal engine (implicit spec Errata D13): the basics of what comes back. Its agreement with the CPU mesher is
/// `GPUMeshAgreementTests`; its limits are `MetalMeshingLimitsTests`. Skipped on a machine without a Metal device.
@Suite(.enabled(if: MetalImplicitEngine.shared != nil, "needs a Metal device"))
struct MetalMeshingTests {
    /// The request for every brick of `solid` at `resolution`, planned on the CPU.
    static func request(_ solid: ImplicitSolid, resolution: Double, snap: Bool = true) async throws -> BrickMeshRequest {
        BrickMeshRequest(plan: try await BrickPlan.build(for: solid, resolution: resolution, using: CPUBatchEvaluator(solid)), snap: snap)
    }

    @Test func aSphereMeshedOnTheGPUIsAClosedManifoldWithTheRightVolume() async throws {
        let engine = try #require(MetalImplicitEngine.shared)
        let solid = ImplicitSolid.sphere(radius: 10)
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: engine)
        #expect(selection.evaluator.engineName == "Metal")
        let (mesh, path) = try await ImplicitMesher(evaluator: selection.evaluator)
            .meshReportingPath(solid, resolution: 0.53, quality: .export)
        #expect(path == .gpu)
        let topology = MeshTopology(mesh)
        #expect(topology.isClosedManifold && topology.eulerCharacteristic == 2)
        let exact = 4.0 / 3 * Double.pi * 1000
        #expect(abs(mesh.signedVolume - exact) / exact < 0.005, "volume \(mesh.signedVolume) against \(exact)")
        #expect(mesh.normals.count == mesh.positions.count && mesh.normals.allSatisfy { abs(($0 * $0).sum() - 1) < 1e-4 })
    }

    @Test func withoutTheSnapTheNormalsAreZeroAndTheVerticesAreOnTheLattice() async throws {
        let engine = try #require(MetalImplicitEngine.shared)
        let solid = ImplicitFixtures.sphere
        let program = try await engine.compile(solid)
        let request = try await Self.request(solid, resolution: 0.53, snap: false)
        let mesh = try await engine.meshBricks(program, request) { _ in }
        #expect(mesh.isConsistent && !mesh.triangles.isEmpty)
        #expect(mesh.normals.allSatisfy { $0 == .zero })
        // Each vertex is on a lattice edge, so two of its coordinates are lattice coordinates (to Float precision).
        let step = Float(request.resolution)
        for position in mesh.positions.prefix(500) {
            let onLattice = (0..<3).filter { axis in
                let steps = (position[axis] - Float(request.origin[axis])) / step
                return abs(steps - steps.rounded()) < 1e-3
            }
            #expect(onLattice.count >= 2, "\(position) is not on an edge of the lattice")
        }
    }

    @Test func noBricksIsAnEmptyMesh() async throws {
        let engine = try #require(MetalImplicitEngine.shared)
        let program = try await engine.compile(.sphere(radius: 5))
        let mesh = try await engine.meshBricks(program, BrickMeshRequest(origin: .zero, resolution: 1, bricks: [], snap: true)) { _ in }
        #expect(mesh == BrickMesh(positions: [], normals: [], triangles: []))
    }

    @Test func solidsOfOneShapeShareTheMeshingKernels() async throws {
        let engine = try #require(MetalImplicitEngine())
        for radius in [5.0, 7.5] {
            let solid = ImplicitSolid.sphere(radius: radius)
            let program = try await engine.compile(solid)
            let mesh = try await engine.meshBricks(program, try await Self.request(solid, resolution: 0.7)) { _ in }
            let asMesh = TriangleMesh(positions: mesh.positions, normals: mesh.normals, triangles: mesh.triangles)
            #expect(MeshTopology(asMesh).isClosedManifold)
        }
        #expect(await engine.meshCompileCount == 1)
        let box = ImplicitSolid.box(halfSize: Vector3(3, 3, 3), cornerRadius: 0.5)
        _ = try await engine.meshBricks(try await engine.compile(box), try await Self.request(box, resolution: 0.7)) { _ in }
        #expect(await engine.meshCompileCount == 2)
        #expect(await engine.meshesMade == 3)
    }

    @Test func progressRisesAndNeverPassesOne() async throws {
        let engine = try #require(MetalImplicitEngine.shared)
        let solid = ImplicitFixtures.cylinder
        let seen = ProgressLog()
        _ = try await engine.meshBricks(try await engine.compile(solid), try await Self.request(solid, resolution: 0.6)) { seen.append($0) }
        let values = seen.values
        #expect(values.count >= 3 && values == values.sorted() && (values.last ?? 0) > 0.9 && (values.last ?? 2) <= 1)
    }
}
#endif
