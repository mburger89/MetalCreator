import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// Meshing on the HLSL engine (plan xp-c; Errata D13): the basics, as `MetalMeshingTests` for Metal. Agreement with the CPU is `GPUMeshAgreementTests`.
@Suite(.enabled(if: GPUEnginesUnderTest.hlsl != nil, "needs the HLSL engine: \(GPUEnginesUnderTest.unavailableReason)"))
struct HLSLMeshingTests {
    static func request(_ solid: ImplicitSolid, resolution: Double, snap: Bool = true) async throws -> BrickMeshRequest {
        BrickMeshRequest(plan: try await BrickPlan.build(for: solid, resolution: resolution, using: CPUBatchEvaluator(solid)), snap: snap)
    }

    @Test func aSphereMeshedOnTheGPUIsAClosedManifoldWithTheRightVolume() async throws {
        let engine = try #require(GPUEnginesUnderTest.hlsl)
        let solid = ImplicitSolid.sphere(radius: 10)
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: engine)
        #expect(selection.evaluator.engineName == engine.name)
        let (mesh, path) = try await ImplicitMesher(evaluator: selection.evaluator)
            .meshReportingPath(solid, resolution: 0.53, quality: .export)
        #expect(path == .gpu)
        let topology = MeshTopology(mesh)
        #expect(topology.isClosedManifold && topology.eulerCharacteristic == 2)
        let exact = 4.0 / 3 * Double.pi * 1000
        #expect(abs(mesh.signedVolume - exact) / exact < 0.005)
        #expect(mesh.normals.count == mesh.positions.count && mesh.normals.allSatisfy { abs(($0 * $0).sum() - 1) < 1e-4 })
    }

    @Test func withoutTheSnapTheNormalsAreZeroAndTheVerticesAreOnTheLattice() async throws {
        let engine = try #require(GPUEnginesUnderTest.hlsl)
        let program = try await engine.compile(ImplicitFixtures.sphere)
        let request = try await Self.request(ImplicitFixtures.sphere, resolution: 0.53, snap: false)
        let mesh = try await engine.meshBricks(program, request) { _ in }
        #expect(mesh.isConsistent && !mesh.triangles.isEmpty && mesh.normals.allSatisfy { $0 == .zero })
        let step = Float(request.resolution)
        for position in mesh.positions {
            let onLattice = (0..<3).filter { axis in
                let units = (position[axis] - Float(request.origin[axis])) / step
                return abs(units - units.rounded()) < 1e-3
            }
            #expect(onLattice.count >= 2, "\(position) is on a lattice edge")
        }
    }

    /// Review Focus 3: a shape's meshing pipelines are made once; a second shape makes only its three that call `sdf` (the four others are shared).
    @Test func meshingASecondTimeCompilesNoMeshPipeline() async throws {
        let engine = try #require(GPUEnginesUnderTest.makeHLSL())
        let sphere = try await engine.compile(.sphere(radius: 3))
        let request = try await Self.request(.sphere(radius: 3), resolution: 0.5)
        _ = try await engine.meshBricks(sphere, request) { _ in }
        #expect(await engine.meshCompileCount == 6)
        _ = try await engine.meshBricks(try await engine.compile(.sphere(radius: 4)), request) { _ in }
        #expect(await engine.meshCompileCount == 6, "the same shape")
        let box = try await engine.compile(.box(halfSize: Vector3(2, 2, 2), cornerRadius: 0))
        let boxRequest = try await Self.request(.box(halfSize: Vector3(2, 2, 2), cornerRadius: 0), resolution: 0.5)
        _ = try await engine.meshBricks(box, boxRequest) { _ in }
        #expect(await engine.meshCompileCount == 8, "sample and place for the box; clear, classify, number and emit shared")
    }
}
