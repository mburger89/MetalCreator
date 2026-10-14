import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorImplicit

/// Engine selection, tested with `StubGPUEngine` so it runs on every platform; the Metal engine's own cases follow, where Metal exists.
struct ImplicitEvaluatorsTests {
    static let profileSolid: ImplicitSolid = {
        let profile = Profile2D.rectangle(width: 4, height: 4, plane: .xy)
        let graded = Grading(field: .distance(.profile(profile), signed: false), range: 0...10, slope: 1)
        return ImplicitSolid.offset(.sphere(radius: 3), distance: graded)
    }()

    @Test func theCPUChoiceIsAlwaysTheCPUWithNoWarning() async {
        let selection = await ImplicitEvaluators.make(for: ImplicitFixtures.sphere, choice: .cpu, engine: StubGPUEngine())
        #expect(selection.evaluator.engineName == "CPU" && selection.warning == nil)
    }

    @Test func noGPUEngineMeansTheCPUAndNoWarning() async {
        let selection = await ImplicitEvaluators.make(for: ImplicitFixtures.sphere, choice: .automatic, engine: nil)
        #expect(selection.evaluator.engineName == "CPU" && selection.warning == nil && selection.diagnostic == nil)
    }

    @Test func automaticUsesTheGPUEngineWhenItCan() async throws {
        let engine = StubGPUEngine()
        let selection = await ImplicitEvaluators.make(for: ImplicitFixtures.cylinder, choice: .automatic, engine: engine)
        #expect(selection.evaluator.engineName == "Stub" && selection.warning == nil)
        let values = try await selection.evaluator.evaluate([SIMD3(0, 0, 100)])
        #expect(values.count == 1 && values[0] > 0)
        #expect(await engine.prepared == 1)
    }

    @Test func aSolidTheGPUCannotDoRunsOnTheCPUWithAWarning() async {
        let engine = StubGPUEngine(failure: .unsupported("a distance to a profile"))
        let selection = await ImplicitEvaluators.make(for: Self.profileSolid, choice: .automatic, engine: engine)
        #expect(selection.evaluator.engineName == "CPU" && selection.warning == "Running on the CPU")
        #expect(selection.diagnostic?.contains("a distance to a profile") == true)
    }

    @Test func aCompilerFailureAlsoFallsBackToTheCPUWithAWarning() async {
        let engine = StubGPUEngine(failure: .engine("a made-up error"))
        let selection = await ImplicitEvaluators.make(for: ImplicitFixtures.sphere, choice: .automatic, engine: engine)
        #expect(selection.evaluator.engineName == "CPU" && selection.warning == ImplicitEvaluators.cpuWarning)
    }

    @Test func aMeshFromTheCPUEngineIsClosedAndManifold() async throws {
        let solid = ImplicitFixtures.all[5].solid
        let selection = await ImplicitEvaluators.make(for: solid, choice: .cpu)
        let mesh = try await ImplicitMesher(evaluator: selection.evaluator).mesh(solid, resolution: 0.5, quality: .preview)
        #expect(MeshTopology(mesh).isClosedManifold)
    }
}

#if canImport(Metal)
/// The same selection with the real engine, on a machine with a Metal device.
@Suite(.enabled(if: MetalImplicitEngine.shared != nil, "needs a Metal device"))
struct MetalEvaluatorsTests {
    @Test func theMachinesDefaultIsMetalAndMetalCanDoACylinder() async {
        let selection = await ImplicitEvaluators.make(for: ImplicitFixtures.cylinder, choice: .automatic)
        #expect(selection.evaluator.engineName == "Metal" && selection.warning == nil)
    }

    @Test func aDistanceToAProfileRunsOnTheCPUWithAWarning() async {
        let selection = await ImplicitEvaluators.make(for: ImplicitEvaluatorsTests.profileSolid, choice: .automatic)
        #expect(selection.evaluator.engineName == "CPU" && selection.warning == "Running on the CPU")
    }

    @Test func aMeshFromTheGPUIsAsGoodAsOneFromTheCPU() async throws {
        let solid = ImplicitFixtures.all[5].solid
        let gpu = await ImplicitEvaluators.make(for: solid, choice: .automatic)
        #expect(gpu.evaluator.engineName == "Metal")
        let fromGPU = try await ImplicitMesher(evaluator: gpu.evaluator).mesh(solid, resolution: 0.5, quality: .preview)
        let fromCPU = try await ImplicitMesher(evaluator: CPUBatchEvaluator(solid)).mesh(solid, resolution: 0.5, quality: .preview)
        #expect(MeshTopology(fromGPU).isClosedManifold)
        #expect(abs(Double(fromGPU.triangleCount - fromCPU.triangleCount)) / Double(fromCPU.triangleCount) < 0.01)
        #expect(abs(fromGPU.signedVolume - fromCPU.signedVolume) / fromCPU.signedVolume < 0.002)
    }

    /// Cross-brick watertightness assumes both sides of a brick face sample the same value there (implicit spec §4.2). The mesher cannot
    /// check that, so every fixture spans several bricks (8 voxels, 4 mm at 0.5 mm) and must come out of the GPU as the CPU's topology.
    @Test func everyFixtureMeshesToTheSameTopologyOnTheGPUAsOnTheCPU() async throws {
        for (name, solid) in ImplicitFixtures.all {
            let gpu = await ImplicitEvaluators.make(for: solid, choice: .automatic)
            guard gpu.evaluator.engineName == "Metal" else { continue }
            let bricks = Double(BrickPlan.brickSize) * 0.5
            #expect(solid.bounds.size.x > 2 * bricks, "\(name) spans several bricks")
            let fromGPU = try await ImplicitMesher(evaluator: gpu.evaluator).mesh(solid, resolution: 0.5, quality: .preview)
            let fromCPU = try await ImplicitMesher(evaluator: CPUBatchEvaluator(solid)).mesh(solid, resolution: 0.5, quality: .preview)
            let (topologyGPU, topologyCPU) = (MeshTopology(fromGPU), MeshTopology(fromCPU))
            #expect(topologyGPU.openEdgeCount == topologyCPU.openEdgeCount, "\(name): open edges")
            #expect(topologyGPU.overfullEdgeCount == topologyCPU.overfullEdgeCount, "\(name): overfull edges")
            #expect(topologyGPU.isClosedManifold == topologyCPU.isClosedManifold, "\(name): closed and manifold")
            if topologyCPU.isClosedManifold {
                #expect(topologyGPU.eulerCharacteristic == topologyCPU.eulerCharacteristic, "\(name): Euler characteristic")
            }
        }
    }
}
#endif
