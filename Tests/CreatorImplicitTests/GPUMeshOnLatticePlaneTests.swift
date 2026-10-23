import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// A surface lying exactly on a mesher lattice plane or the domain's face, on every GPU engine (plan xp-c, the last Windows failure:
/// on D3D12 the noisy shell's outer surface is the bounds face x = -8, where the field is 0 give or take an ulp, so the place kernel met
/// an edge whose re-evaluated ends were equal, `fa / (fa - fb)` was ±inf or NaN, and a vertex had z = -inf and a zero normal).
/// The meshes have only finite vertices and normals, and agree with the CPU's.
@Suite(.enabled(if: !GPUEnginesUnderTest.names.isEmpty, "needs a GPU engine: \(GPUEnginesUnderTest.unavailableReason)"))
struct GPUMeshOnLatticePlaneTests {
    /// Boxes with sharp edges and faces on the bounds, meshed at voxel sizes that divide them, so the faces are lattice planes and the
    /// samples there are exactly 0; and the noisy shell, whose outer surface is the box's face.
    static let solids: [(name: String, solid: ImplicitSolid, resolution: Double)] = [
        ("sharp box, faces on lattice planes", .box(halfSize: Vector3(8, 6, 4), cornerRadius: 0), 0.5),
        ("sharp box, faces on every other plane", .box(halfSize: Vector3(8, 6, 4), cornerRadius: 0), 1),
        ("noisy shell", GPUFixtures.all.first { $0.name == "noisy shell" }!.solid, 0.53),
    ]
    static let names = solids.map(\.name)

    @Test(arguments: GPUEnginesUnderTest.names, names)
    func aSurfaceOnALatticePlaneMeshesFiniteAndLikeTheCPU(_ engineName: String, _ name: String) async throws {
        let fixture = try #require(Self.solids.first { $0.name == name })
        let (solid, resolution) = (fixture.solid, fixture.resolution)
        let engine = try GPUEnginesUnderTest.engine(engineName)
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: engine)
        let gpu = try await ImplicitMesher(evaluator: selection.evaluator)
            .meshReportingPath(solid, resolution: resolution, quality: .preview)
        #expect(gpu.path == .gpu, "\(engineName), \(name): the GPU mesher ran")
        let finite = { (v: SIMD3<Float>) in v.x.isFinite && v.y.isFinite && v.z.isFinite }
        let bad = gpu.mesh.positions.indices.filter { !finite(gpu.mesh.positions[$0]) || !finite(gpu.mesh.normals[$0]) }
        #expect(bad.isEmpty, "\(engineName), \(name): \(bad.count) of \(gpu.mesh.positions.count) vertices or normals are not finite")
        guard bad.isEmpty else { return }

        let reference = try await ImplicitMesher(evaluator: CPUBatchEvaluator(solid)).mesh(solid, resolution: resolution, quality: .preview)
        GPUMeshAgreementTests.expectSameTopology(gpu.mesh, reference, name, engineName)
        let slopes = try await GPUMeshAgreementTests.slopes(of: solid, at: reference.positions)
        let pipeline = MeshComparison(reference: reference, candidate: gpu.mesh, slopes: slopes)
        #expect(pipeline.unmatched == 0, "\(engineName), \(name): vertices without a match")
        #expect(pipeline.worstScaledSurface <= GPUFixtures.meshAllowanceFactor(name),
                "\(engineName), \(name): surfaces \(pipeline.worstScaledDetail.along) mm apart")
        #expect(pipeline.farthest <= GPUMeshAgreementTests.slideTolerance, "\(engineName), \(name): farthest \(pipeline.farthest) mm")
        #expect(pipeline.smallestNormalDot >= GPUMeshAgreementTests.pipelineNormalDot,
                "\(engineName), \(name): normal dot \(pipeline.smallestNormalDot)")
    }
}
