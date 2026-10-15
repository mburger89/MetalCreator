import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorImplicit

/// The stream a Mesh node hands over while an export streams (implicit spec Errata D12).
struct MeshStreamTests {
    let ball = ImplicitSolid.sphere(radius: 5)

    @Test func aStreamIsNothingMeshedYetAndSaysSo() {
        let stream = MeshStream(solid: ball, resolution: 0.1)
        #expect(stream.triangleCount == 0 && stream.estimatedBytes < 1_000)
        #expect(stream.inspectorFacts == [PayloadFact("Export", "Streamed to the file at 0.1 mm")])
        let slim = stream.appending(.decimate(tolerance: 0.02))
        #expect(slim.stages == [.decimate(tolerance: 0.02)] && stream.stages.isEmpty, "appending makes a new stream")
        #expect(slim.inspectorFacts.last == PayloadFact("Decimate", "within 0.02 mm"))
    }

    @Test func materializedIsTheMeshWithItsStagesApplied() async throws {
        let stream = MeshStream(solid: ball, resolution: 0.4)
        let plain = try await stream.materialized(limit: 100_000, using: CPUBatchEvaluator(ball))
        #expect(MeshTopology(plain).isClosedManifold && plain.quality == .export && plain.resolution == 0.4)
        let slim = try await stream.appending(.decimate(tolerance: 0.05)).materialized(limit: 100_000, using: CPUBatchEvaluator(ball))
        #expect(MeshTopology(slim).isClosedManifold && slim.triangleCount < plain.triangleCount)
    }

    @Test func pastTheLimitItSaysHowManyTrianglesThereAre() async throws {
        let stream = MeshStream(solid: ball, resolution: 0.4)
        let all = try await stream.materialized(limit: .max, using: CPUBatchEvaluator(ball))
        await #expect(throws: MeshStream.Failure.tooManyTriangles(all.triangleCount)) {
            try await stream.materialized(limit: 100, using: CPUBatchEvaluator(ball))
        }
    }

    @Test func aCheckCopyIsAtTheStreamsResolutionWhenItFits() async throws {
        let stream = MeshStream(solid: ball, resolution: 0.4)
        let copy = try await stream.checkCopy(using: CPUBatchEvaluator(ball))
        #expect(copy.isExact && MeshTopology(copy.mesh).isClosedManifold && copy.mesh.resolution == 0.4)
    }

    @Test func aCheckCopyOfAPartThatIsTooBigIsCoarserAndSaysSo() async throws {
        let stream = MeshStream(solid: ball, resolution: 0.1)
        let copy = try await stream.checkCopy(using: CPUBatchEvaluator(ball), triangleBudget: 3_000)
        #expect(!copy.isExact && copy.mesh.resolution > 0.1)
        #expect(copy.mesh.triangleCount < 12_000, "about the budget, not the 120,000 an exact copy needs")
    }

    @Test func aStreamOfNothingIsRefused() async {
        let tiny = ImplicitSolid.sphere(radius: 0.01)
        await #expect(throws: ImplicitMeshingError.empty) {
            try await MeshStream(solid: tiny, resolution: 0.5).materialized(limit: 10, using: CPUBatchEvaluator(tiny))
        }
    }

    @Test func theCollectorAndTheCounterTakeWindows() throws {
        var collector = MeshCollector(limit: 20)
        let cube = MeshFixtures.cube
        try collector.add(MeshWindow(positions: cube.positions, triangles: cube.triangles, startingAt: 0))
        #expect(collector.triangleCount == 12 && collector.vertexCount == 8)
        #expect(throws: MeshCollector.Overflow()) {
            try collector.add(MeshWindow(positions: cube.positions, triangles: cube.triangles, startingAt: 8))
        }
        var counter = MeshCounter()
        try counter.add(MeshWindow(positions: cube.positions, triangles: cube.triangles, startingAt: 0))
        try counter.add(MeshWindow(positions: cube.positions, triangles: cube.triangles, startingAt: 8))
        #expect(counter.triangleCount == 24 && counter.vertexCount == 16)
    }
}
