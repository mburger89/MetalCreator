#if canImport(Metal)
import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// The streamed export on the GPU engine's values (implicit spec Errata D12, D13): the streamer meshes on the CPU over whatever evaluator
/// it is given, and the windows are welded by the exact bits of their shared vertices, so the GPU evaluator has to return the same bits
/// for the same point in different batches. Skipped on a machine without a Metal device.
@Suite(.enabled(if: MetalImplicitEngine.shared != nil, "needs a Metal device"))
struct StreamingMesherGPUTests {
    @Test func aSphereStreamedInSeveralWindowsOnTheGPUIsTheMeshOfOneWindow() async throws {
        let solid = ImplicitSolid.sphere(radius: 10)
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic)
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
}
#endif
