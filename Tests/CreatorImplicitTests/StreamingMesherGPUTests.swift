import CreatorGeometry
import Foundation
import Testing
@testable import CreatorImplicit

/// The streamed export on the GPU engine's values (implicit spec Errata D12, D13): the streamer meshes on the CPU over whatever evaluator
/// it is given, and the windows are welded by the exact bits of their shared vertices, so the GPU evaluator has to return the same bits
/// for the same point in different batches. Run over every GPU engine this machine has.
@Suite(.enabled(if: !GPUEnginesUnderTest.names.isEmpty, "needs a GPU engine: \(GPUEnginesUnderTest.unavailableReason)"))
struct StreamingMesherGPUTests {
    @Test(arguments: GPUEnginesUnderTest.names)
    func aSphereStreamedInSeveralWindowsOnTheGPUIsTheMeshOfOneWindow(_ engineName: String) async throws {
        let solid = ImplicitSolid.sphere(radius: 10)
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: try GPUEnginesUnderTest.engine(engineName))
        try #require(selection.evaluator.engineName != "CPU", "the GPU evaluator was chosen")
        var windows = CollectingSink()
        let many = try await StreamingMesher(evaluator: selection.evaluator, windowBricks: 6, bricksPerBatch: 5)
            .stream(solid, resolution: 0.5, into: &windows)
        var single = CollectingSink()
        let one = try await StreamingMesher(evaluator: selection.evaluator, windowBricks: 1_000_000)
            .stream(solid, resolution: 0.5, into: &single)
        #expect(many.windows >= 4 && one.windows == 1, "\(many.windows) windows against \(one.windows)")
        #expect(many.sharedVertices > 0, "the seams were welded")
        #expect(windows.mesh.vertexCount == single.mesh.vertexCount && windows.mesh.triangleCount == single.mesh.triangleCount)
        let topology = MeshTopology(windows.mesh)
        #expect(topology.isClosedManifold && topology.eulerCharacteristic == 2, "\(topology)")
    }

    @Test(arguments: GPUEnginesUnderTest.names)
    func aGyroidLatticeStreamedInSeveralWindowsOnTheGPUIsTheMeshOfOneWindow(_ engineName: String) async throws {
        // A lattice has thousands of surface patches crossing every seam, and each has to meet its neighbour.
        let solid = LatticeFixtures.tpmsAll[0].solid
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: try GPUEnginesUnderTest.engine(engineName))
        try #require(selection.evaluator.engineName != "CPU", "the GPU evaluator was chosen")
        var windows = CollectingSink()
        let many = try await StreamingMesher(evaluator: selection.evaluator, windowBricks: 40, bricksPerBatch: 50)
            .stream(solid, resolution: 0.5, into: &windows)
        var single = CollectingSink()
        let one = try await StreamingMesher(evaluator: selection.evaluator, windowBricks: 1_000_000)
            .stream(solid, resolution: 0.5, into: &single)
        #expect(many.windows >= 3 && one.windows == 1, "\(many.windows) windows against \(one.windows)")
        #expect(many.sharedVertices > 0, "the seams were welded")
        #expect(windows.mesh.vertexCount == single.mesh.vertexCount && windows.mesh.triangleCount == single.mesh.triangleCount)
        #expect(MeshTopology(windows.mesh).isClosedManifold, "\(MeshTopology(windows.mesh))")
    }

    /// Review Focus 6, X-C3: an export streams through the CPU mesher over the engine's values, in the plan's order, so the same solid exported twice
    /// on one machine is the same bytes, on every engine (Metal's today, and the HLSL engine's). Across machines or backends the values may differ in a
    /// last bit and the bytes with them; D15's tolerances are what holds there.
    @Test(arguments: GPUEnginesUnderTest.names)
    func exportingTheSameSolidTwiceGivesTheSameBytes(_ engineName: String) async throws {
        let solid = LatticeFixtures.tpmsAll[0].solid
        let engine = try GPUEnginesUnderTest.engine(engineName)
        func export() async throws -> Data {
            let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: engine)
            let url = FileManager.default.temporaryDirectory.appending(path: "xp-c-\(UUID().uuidString).stl")
            defer { try? FileManager.default.removeItem(at: url) }
            var sink = try STLFileWriter(destination: url)
            _ = try await StreamingMesher(evaluator: selection.evaluator, windowBricks: 40, bricksPerBatch: 50)
                .stream(solid, resolution: 0.5, into: &sink)
            try sink.finish()
            return try Data(contentsOf: url)
        }
        let first = try await export()
        let second = try await export()
        #expect(!first.isEmpty && first == second, "\(engineName): two exports differ")
    }
}
