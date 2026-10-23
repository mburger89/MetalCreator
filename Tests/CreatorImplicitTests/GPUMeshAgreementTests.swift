import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// The GPU mesher against the CPU mesher (implicit spec §4.3, §7, Errata D13): the same fixtures as the evaluator's agreement suite,
/// meshed both ways. Run over every GPU engine this machine has (`GPUEnginesUnderTest`), skipped on a machine with none.
///
/// Two comparisons, because there are two things that can differ:
/// - **The mesher**, with the same sample values: the CPU mesher over the GPU engine's values (what meshing was before D13) against
///   the GPU mesher. The same topology, the same triangle count, and every vertex within 1e-4 mm (D13). On the fixtures the largest
///   difference is about 2e-5 mm.
/// - **The whole pipeline**: the CPU mesher over the CPU evaluator, the reference, against the GPU's. The evaluators agree to 1e-4
///   mm (`GPUAgreementTests`) and the mesh interpolates along lattice edges, so where an edge runs nearly tangent to the surface a
///   value difference of 1e-6 slides the vertex along the surface by 1e-4 or more: on the fixtures up to 9e-4 mm, with the surfaces
///   themselves within 2e-5 mm. So the surfaces must agree within 1e-4 mm (along the reference's normal), the vertices within 2e-3.
///
/// A mapped lattice whose lattice coordinates reach 40 to 70 mm is allowed twice D17's surface allowance (`GPUFixtures.meshMarginal`).
///
/// Both numbers are for parts within a few hundred millimetres of the origin: positions are `Float`, and one unit in the last place
/// is 5e-4 mm at 4 m, so D13's 1e-4 mm cannot hold for a far part (`MetalMeshingLimitsTests` checks that one's bounds to 1 mm).
/// The normals (dot product at least 0.9999 on the same samples, 0.999 whole) and the enclosed volume (1e-3, and positive: a
/// reversed winding is negative) are held too, because `MeshTopology` sees neither an inverted normal nor an inside-out mesh.
@Suite(.enabled(if: !GPUEnginesUnderTest.names.isEmpty, "needs a GPU engine: \(GPUEnginesUnderTest.unavailableReason)"))
struct GPUMeshAgreementTests {
    /// Errata D13: vertices within 1e-4 mm after the snap.
    static let vertexTolerance: Float = 1e-4
    /// The whole pipeline's slide along the surface (see above).
    static let slideTolerance: Float = 2e-3
    /// Spec erratum D17: the whole pipeline's surfaces agree within 1e-4 mm divided by the field's local slope (the magnitude of its
    /// gradient at the surface point, by central differences on the CPU evaluator), never less than 1e-4 mm. The evaluators agree to
    /// 1e-4 in value (`GPUAgreementTests`), and a value difference of that moves the surface by 1e-4 / slope: a graded cell or a noisy
    /// wall has a slope below 1 (measured: graded diamond 1.1e-4 mm, noisy neovius 2.5e-4 mm). A plain shape has slope about 1 and
    /// keeps 1e-4 mm. The mesher alone keeps `vertexTolerance` everywhere.
    static let slopeStep: Float = 0.01

    /// The slope of `solid`'s field at each of `points`, by central differences on the CPU evaluator.
    static func slopes(of solid: ImplicitSolid, at points: [SIMD3<Float>]) async throws -> [Float] {
        let h = slopeStep
        let axes: [SIMD3<Float>] = [SIMD3(h, 0, 0), SIMD3(0, h, 0), SIMD3(0, 0, h)]
        let samples = points.flatMap { point in axes.flatMap { [point + $0, point - $0] } }
        let values = try await CPUBatchEvaluator(solid).evaluate(samples)
        return points.indices.map { index in
            let base = index * 6
            let gradient = SIMD3((values[base] - values[base + 1]), (values[base + 2] - values[base + 3]),
                                 (values[base + 4] - values[base + 5])) / (2 * h)
            return (gradient * gradient).sum().squareRoot()
        }
    }
    /// The normals of the two meshers on the same samples: the dot product of a vertex's two normals, at least. They are the snap's
    /// gradient, so the same values give the same direction to rounding.
    static let mesherNormalDot: Float = 0.9999
    /// The normals of the two whole pipelines (the evaluators differ by 1e-6, which turns a gradient by a little more).
    static let pipelineNormalDot: Float = 0.999
    /// The volumes the two meshes enclose, as a fraction: it is the same surface, and a reversed winding changes its sign.
    static let volumeTolerance = 1e-3
    /// The triangle counts of the two meshers, as a fraction. They are equal on every fixture; a sample within a rounding of zero
    /// can move a handful of triangles, so a thousandth is allowed.
    static let triangleTolerance = 0.001

    /// The fixtures that make a surface. (The GPU suite's "implicit leaf" offsets a ball by its own distance and has none, and an
    /// "empty …" fixture is an empty combination, which meshing refuses: `ImplicitMeshingError.empty`.)
    static let names = GPUFixtures.all.map(\.name).filter { $0 != "implicit leaf" && !$0.hasPrefix("empty") }

    /// A voxel size off the lattice's round numbers, so no sample lands on a surface, about 60 voxels across the fixture. Coarser
    /// than that the Newton step lands on the kinks of a shell or a noisy field, where its gradient is small and it amplifies the
    /// difference between two evaluators (the noisy shell's surfaces were 6e-4 mm apart at 1.5 mm voxels): see the plan's risks.
    static func resolution(of solid: ImplicitSolid) -> Double {
        let size = solid.bounds.size
        return max(0.53, max(size.x, size.y, size.z) / 60)
    }

    static func expectSameTopology(_ gpu: TriangleMesh, _ cpu: TriangleMesh, _ name: String, _ engineName: String) {
        let (g, c) = (MeshTopology(gpu), MeshTopology(cpu))
        #expect(g.isClosedManifold && c.isClosedManifold, "\(engineName), \(name): closed and manifold")
        #expect(g.eulerCharacteristic == c.eulerCharacteristic,
                "\(engineName), \(name): Euler \(g.eulerCharacteristic) against \(c.eulerCharacteristic)")
        let difference = Double(abs(g.triangleCount - c.triangleCount)) / Double(c.triangleCount)
        #expect(difference <= triangleTolerance, "\(engineName), \(name): \(g.triangleCount) triangles against \(c.triangleCount)")
        #expect(abs(gpu.vertexCount - cpu.vertexCount) <= max(1, Int(Double(cpu.vertexCount) * triangleTolerance)),
                "\(engineName), \(name): vertices")
        // Triangles wind counter-clockwise seen from outside, like the CPU's: `MeshTopology` only checks that they agree with each
        // other, so the enclosed volume (negative for a mesh turned inside out) is what tells.
        #expect(cpu.signedVolume > 0, "\(engineName), \(name): the reference is wound outwards")
        #expect(gpu.signedVolume > 0 && abs(gpu.signedVolume - cpu.signedVolume) <= volumeTolerance * cpu.signedVolume,
                "\(engineName), \(name): volume \(gpu.signedVolume) against \(cpu.signedVolume)")
    }

    @Test(arguments: GPUEnginesUnderTest.names, names)
    func theGPUMeshAgreesWithTheCPUMesh(_ engineName: String, _ name: String) async throws {
        let engine = try GPUEnginesUnderTest.engine(engineName)
        let solid = try #require(GPUFixtures.all.first { $0.name == name }?.solid)
        let resolution = Self.resolution(of: solid)
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: engine)
        let gpu = try await ImplicitMesher(evaluator: selection.evaluator)
            .meshReportingPath(solid, resolution: resolution, quality: .preview)
        #expect(gpu.path == .gpu, "\(engineName), \(name): the GPU mesher ran")

        // The mesher alone: the same sample values.
        let sameSamples = try await ImplicitMesher(evaluator: SamplesOnlyEvaluator(inner: selection.evaluator))
            .meshReportingPath(solid, resolution: resolution, quality: .preview)
        #expect(sameSamples.path == .cpu)
        Self.expectSameTopology(gpu.mesh, sameSamples.mesh, name, engineName)
        let mesher = MeshComparison(reference: sameSamples.mesh, candidate: gpu.mesh)
        #expect(mesher.unmatched == 0, "\(engineName), \(name): vertices without a match")
        #expect(mesher.farthest <= Self.vertexTolerance, "\(engineName), \(name): the largest vertex difference is \(mesher.farthest) mm")
        #expect(mesher.smallestNormalDot >= Self.mesherNormalDot,
                "\(engineName), \(name): a normal differs: dot \(mesher.smallestNormalDot)")

        // The whole pipeline: the CPU evaluator is the reference.
        let reference = try await ImplicitMesher(evaluator: CPUBatchEvaluator(solid)).mesh(solid, resolution: resolution, quality: .preview)
        Self.expectSameTopology(gpu.mesh, reference, name, engineName)
        let slopes = try await Self.slopes(of: solid, at: reference.positions)
        let pipeline = MeshComparison(reference: reference, candidate: gpu.mesh, slopes: slopes)
        #expect(pipeline.unmatched == 0, "\(engineName), \(name): vertices without a match")
        let detail = pipeline.worstScaledDetail
        let factor = GPUFixtures.meshAllowanceFactor(name)
        let apart = "surfaces \(detail.along) mm apart, \(detail.allowed) allowed (× \(factor))"
        #expect(pipeline.worstScaledSurface <= factor, "\(engineName), \(name): \(apart)")
        #expect(pipeline.farthest <= Self.slideTolerance,
                "\(engineName), \(name): the largest vertex difference is \(pipeline.farthest) mm")
        #expect(pipeline.smallestNormalDot >= Self.pipelineNormalDot,
                "\(engineName), \(name): a normal differs: dot \(pipeline.smallestNormalDot)")
    }

    /// The Face fixtures that hold the cylinder's axis (`GPUFixtures.singularSetNames`), whole pipeline, away from the axis: their values
    /// agree within 1e-4 mm everywhere (`GPUAgreementTests`), but within a few millimetres of the singular set the map multiplies the GPU's
    /// rounding (2e-5 mm) into slides of up to 2e-3 mm along near-tangent mesh edges, so the vertices inside a cylinder of
    /// `GPUFixtures.singularSetExclusion` about the axis are left out and the rest are held to D17's allowance (spec Errata D20). The
    /// topology and the volume are not compared: the exclusion's inside may differ by a triangle or two.
    @Test(arguments: GPUEnginesUnderTest.names, GPUFixtures.singularSetNames)
    func theGPUMeshAgreesAwayFromTheSingularSet(_ engineName: String, _ name: String) async throws {
        let engine = try GPUEnginesUnderTest.engine(engineName)
        let solid = try #require(LatticeFixtures.faceAll.first { $0.name == name }?.solid)
        let resolution = Self.resolution(of: solid)
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: engine)
        let gpu = try await ImplicitMesher(evaluator: selection.evaluator)
            .meshReportingPath(solid, resolution: resolution, quality: .preview)
        #expect(gpu.path == .gpu, "\(engineName), \(name): the GPU mesher ran")
        let reference = try await ImplicitMesher(evaluator: CPUBatchEvaluator(solid)).mesh(solid, resolution: resolution, quality: .preview)
        let slopes = try await Self.slopes(of: solid, at: reference.positions)
        let pipeline = MeshComparison(reference: reference, candidate: gpu.mesh, slopes: slopes, excluding: GPUFixtures.nearSingularSet)
        #expect(pipeline.unmatched == 0, "\(engineName), \(name): vertices without a match")
        let detail = pipeline.worstScaledDetail
        let factor = GPUFixtures.singularSetAllowanceFactor(name)
        let apart = "surfaces \(detail.along) mm apart, \(detail.allowed) allowed (× \(factor))"
        #expect(pipeline.worstScaledSurface <= factor, "\(engineName), \(name): \(apart)")
        #expect(pipeline.farthest <= Self.slideTolerance,
                "\(engineName), \(name): the largest vertex difference is \(pipeline.farthest) mm")
        #expect(pipeline.smallestNormalDot >= Self.pipelineNormalDot,
                "\(engineName), \(name): a normal differs: dot \(pipeline.smallestNormalDot)")
    }

    @Test(arguments: GPUEnginesUnderTest.names, ["sphere", "box", "smooth union", "graded offset"])
    func withoutTheSnapTheVerticesStillAgreeAndTheNormalsAreZero(_ engineName: String, _ name: String) async throws {
        let engine = try GPUEnginesUnderTest.engine(engineName)
        let solid = try #require(GPUFixtures.all.first { $0.name == name }?.solid)
        let resolution = Self.resolution(of: solid)
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: engine)
        let gpu = try await ImplicitMesher(evaluator: selection.evaluator)
            .meshReportingPath(solid, resolution: resolution, quality: .preview, snap: false)
        let cpu = try await ImplicitMesher(evaluator: SamplesOnlyEvaluator(inner: selection.evaluator))
            .mesh(solid, resolution: resolution, quality: .preview, snap: false)
        #expect(gpu.path == .gpu && gpu.mesh.normals.allSatisfy { $0 == .zero })
        Self.expectSameTopology(gpu.mesh, cpu, name, engineName)
        let comparison = MeshComparison(reference: cpu, candidate: gpu.mesh)
        #expect(comparison.unmatched == 0 && comparison.farthest <= Self.vertexTolerance,
                "\(engineName), \(name): \(comparison.farthest) mm")
    }
}
