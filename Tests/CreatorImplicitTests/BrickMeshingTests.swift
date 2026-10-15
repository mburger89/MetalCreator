import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// The mesher's choice between an engine that meshes bricks and the CPU (implicit spec Errata D13), tested with `StubGPUEngine` so it
/// runs on every platform.
struct BrickMeshingTests {
    /// A closed tetrahedron, as an engine might answer.
    static let tetrahedron = BrickMesh(
        positions: [SIMD3<Float>(1, 1, 1), SIMD3<Float>(1, -1, -1), SIMD3<Float>(-1, 1, -1), SIMD3<Float>(-1, -1, 1)],
        normals: [SIMD3<Float>](repeating: .zero, count: 4), triangles: [0, 1, 2, 0, 3, 1, 0, 2, 3, 1, 3, 2])

    func mesher(_ engine: StubGPUEngine, for solid: ImplicitSolid) async -> ImplicitMesher {
        ImplicitMesher(evaluator: await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: engine).evaluator)
    }

    @Test func anEngineThatMeshesBricksMakesTheMesh() async throws {
        let engine = StubGPUEngine(meshing: .answers(Self.tetrahedron))
        let solid = ImplicitFixtures.sphere
        let (mesh, path) = try await mesher(engine, for: solid).meshReportingPath(solid, resolution: 1, quality: .preview)
        #expect(path == .gpu)
        #expect(mesh.positions == Self.tetrahedron.positions && mesh.triangles == Self.tetrahedron.triangles)
        #expect(mesh.resolution == 1 && mesh.quality == .preview && mesh.meshingSeconds >= 0)
    }

    @Test func theRequestCarriesThePlansBricksAndTheSnapFlag() async throws {
        let engine = StubGPUEngine(meshing: .answers(Self.tetrahedron))
        let solid = ImplicitFixtures.cylinder
        let plan = try await BrickPlan.build(for: solid, resolution: 0.8, using: CPUBatchEvaluator(solid))
        _ = try await mesher(engine, for: solid).mesh(solid, resolution: 0.8, quality: .preview, snap: false)
        let requests = await engine.meshRequests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.bricks == plan.bricks && request.resolution == 0.8 && request.snap == false)
        #expect(request.origin == SIMD3(plan.origin.x, plan.origin.y, plan.origin.z))
        #expect(BrickMeshRequest(plan: plan, snap: true).snap)
    }

    @Test func anEngineThatDoesNotMeshLeavesItToTheCPU() async throws {
        let engine = StubGPUEngine()
        let solid = ImplicitFixtures.sphere
        let (mesh, path) = try await mesher(engine, for: solid).meshReportingPath(solid, resolution: 0.7, quality: .preview)
        #expect(path == .cpu)
        #expect(MeshTopology(mesh).isClosedManifold)
        #expect(await engine.meshRequests.count == 1, "it was asked, and said no")
    }

    @Test func anEngineThatFailsToMeshFallsBackToTheCPU() async throws {
        for failure in [ImplicitCompileError.engine("a made-up error"), .unsupported("too large")] {
            let engine = StubGPUEngine(meshing: .fails(failure))
            let solid = ImplicitFixtures.sphere
            let (mesh, path) = try await mesher(engine, for: solid).meshReportingPath(solid, resolution: 0.7, quality: .preview)
            #expect(path == .cpu && MeshTopology(mesh).isClosedManifold)
        }
    }

    @Test func aCancelledEngineIsNotSwallowed() async {
        let engine = StubGPUEngine(meshing: .cancels)
        let solid = ImplicitFixtures.sphere
        let mesher = await mesher(engine, for: solid)
        await #expect(throws: CancellationError.self) { try await mesher.mesh(solid, resolution: 0.7, quality: .preview) }
    }

    @Test(arguments: [
        BrickMesh(positions: [.zero, .zero, .zero], normals: [.zero, .zero, .zero], triangles: [0, 1, 7]),
        BrickMesh(positions: [.zero, .zero, .zero], normals: [.zero], triangles: [0, 1, 2]),
        BrickMesh(positions: [.zero, .zero, .zero], normals: [.zero, .zero, .zero], triangles: [0, 1]),
    ])
    func arraysThatDoNotFitTogetherAreNotTrusted(_ wrong: BrickMesh) async throws {
        #expect(!wrong.isConsistent)
        let engine = StubGPUEngine(meshing: .answers(wrong))
        let solid = ImplicitFixtures.sphere
        let (mesh, path) = try await mesher(engine, for: solid).meshReportingPath(solid, resolution: 0.7, quality: .preview)
        #expect(path == .cpu && MeshTopology(mesh).isClosedManifold)
    }

    @Test func aConsistentMeshIsConsistent() {
        #expect(Self.tetrahedron.isConsistent)
        #expect(BrickMesh(positions: [], normals: [], triangles: []).isConsistent)
    }

    @Test func anEmptyAnswerIsNothingToMesh() async {
        let engine = StubGPUEngine(meshing: .answers(BrickMesh(positions: [], normals: [], triangles: [])))
        let solid = ImplicitFixtures.sphere
        let mesher = await mesher(engine, for: solid)
        await #expect(throws: ImplicitMeshingError.empty) { try await mesher.mesh(solid, resolution: 0.7, quality: .preview) }
    }

    @Test func theCPUEvaluatorMeshesOnTheCPUWithoutAskingAnyone() async throws {
        let solid = ImplicitFixtures.sphere
        let (_, path) = try await ImplicitMesher(evaluator: CPUBatchEvaluator(solid))
            .meshReportingPath(solid, resolution: 0.7, quality: .preview)
        #expect(path == .cpu)
    }

    @Test func progressIncludesTheEnginesAndEndsAtOne() async throws {
        let engine = StubGPUEngine(meshing: .answers(Self.tetrahedron))
        let solid = ImplicitFixtures.sphere
        let seen = ProgressLog()
        _ = try await mesher(engine, for: solid).mesh(solid, resolution: 1, quality: .preview) { seen.append($0) }
        #expect(seen.values == [0, 0.5, 1])
    }

    @Test func theDefaultRequirementSaysNotSupportedAndTheEvaluatorAnswersNil() async throws {
        let engine = StubGPUEngine()
        let program = try await engine.compile(.sphere(radius: 5))
        let request = BrickMeshRequest(origin: .zero, resolution: 1, bricks: [SIMD3(0, 0, 0)], snap: true)
        let evaluator = GPUBatchEvaluator(engine: engine, program: program)
        #expect(try await evaluator.meshBricks(request) { _ in } == nil)
        #expect(try await CPUBatchEvaluator(.sphere(radius: 5)).meshBricks(request) { _ in } == nil)
    }
}
