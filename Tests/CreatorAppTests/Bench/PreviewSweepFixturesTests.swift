import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// The preview sweep's fixtures, checked in the default run (the benchmark itself is skipped): the ladder, the sheet, the Mesh node's
/// preview resolution, the rule, and the footprint reading.
@MainActor
struct PreviewSweepFixturesTests {
    @Test func theLadderSpansQuarterOfAMillionToEightMillionTriangles() {
        let ladder = PreviewSweepFixtures.ladder
        #expect(ladder.map(\.targetTriangles) == [250_000, 500_000, 1_000_000, 2_000_000, 4_000_000, 8_000_000])
        #expect(ladder.map(\.name) == ["0.25M", "0.5M", "1M", "2M", "4M", "8M"])
        // Finer voxels for more triangles, and none finer than the preview goes.
        #expect(zip(ladder, ladder.dropFirst()).allSatisfy { $0.resolution > $1.resolution })
        #expect(ladder.allSatisfy { $0.resolution >= PreviewSchedule.finest })
    }

    @Test func theSheetIsAClosedSurfaceWhoseTrianglesGrowAsTheVoxelsShrink() async throws {
        let solid = try await ImplicitBenchFixtures.solid(of: PreviewSweepFixtures.sheet(side: 20))
        let mesher = ImplicitMesher(evaluator: CPUBatchEvaluator(solid))
        let coarse = try await mesher.mesh(solid, resolution: 0.8, quality: .preview)
        let fine = try await mesher.mesh(solid, resolution: 0.4, quality: .preview)
        #expect(MeshTopology(fine).isClosedManifold && fine.signedVolume > 0)
        // Halving the voxel size makes about four times the triangles, as `PreviewSchedule` assumes.
        let growth = Double(fine.triangleCount) / Double(coarse.triangleCount)
        #expect(growth > 2.5 && growth < 5.5, "\(coarse.triangleCount) → \(fine.triangleCount) triangles")
    }

    @Test func thePreviewResolutionIsSetOnTheMeshNodeAlone() {
        let sheet = PreviewSweepFixtures.sheet()
        let graph = PreviewSweepFixtures.previewing(sheet.graph, at: 0.9)
        let meshes = graph.nodes.values.filter { $0.typeID == MeshNode.typeID }
        #expect(meshes.count == 1 && meshes.first?.inputValues["preview resolution"] == .number(0.9))
        #expect(graph.nodes.count == sheet.graph.nodes.count)
    }

    @Test func theWallIsThinnerThanTheFixtureOfRowI1() {
        let sheet = PreviewSweepFixtures.sheet()
        #expect(sheet.graph.nodes[sheet.levels.id]?.inputValues["step"] == .number(-PreviewSweepFixtures.wall))
        #expect(PreviewSweepFixtures.cell < ImplicitBenchFixtures.noiseScale)
    }

    // MARK: The rule

    private func rung(_ triangles: Int, gpu: Double = 2, cpu: Double = 5, footprint: Int = 100_000_000, mesh: Double = 100)
        -> PreviewSweepRung {
        let orbit = PreviewSweepRung.Orbit(cpuP95: cpu, gpuP95: gpu)
        return PreviewSweepRung(resolution: 1, triangles: triangles, gpuMeshMilliseconds: mesh, cpuMeshMilliseconds: 10 * mesh,
                                panelShown: orbit, panelHidden: orbit, addedFootprint: footprint)
    }

    @Test func theCapIsTheLastRungBeforeTheFirstFailingRung() {
        let rungs = [rung(250_000), rung(1_000_000), rung(2_000_000, gpu: 7.9), rung(4_000_000, gpu: 8.1), rung(8_000_000)]
        // The 8M rung meets all four again, but it is a pass above a failure: a noisy run, not a cap.
        #expect(PreviewSweepRule.capCandidate(rungs)?.triangles == 2_000_000)
        #expect(PreviewSweepRule.capCandidate(Array(rungs.dropLast()))?.triangles == 2_000_000)
        // Every rung passing: the largest is the cap.
        #expect(PreviewSweepRule.capCandidate(Array(rungs.prefix(3)))?.triangles == 2_000_000)
    }

    @Test func aPassAboveAFailureNeverCounts() {
        // The first rung fails, a later one passes: nothing is the cap, because a rung below the passing one failed.
        #expect(PreviewSweepRule.capCandidate([rung(250_000, gpu: 9), rung(500_000), rung(1_000_000)]) == nil)
        // A failure in the middle ends the scan, whatever comes after it.
        let rungs = [rung(250_000), rung(500_000, footprint: 2_000_000_000), rung(1_000_000), rung(2_000_000)]
        #expect(PreviewSweepRule.capCandidate(rungs)?.triangles == 250_000)
    }

    @Test func eachTestCanFailARungAlone() {
        let smallest = rung(250_000)
        #expect(PreviewSweepRule.verdict(of: rung(1, gpu: 8.5), smallest: smallest) == .init(
            gpuFrame: false, cpuFrame: true, footprint: true, meshing: true))
        #expect(PreviewSweepRule.verdict(of: rung(1, cpu: 6.5), smallest: smallest) == .init(
            gpuFrame: true, cpuFrame: false, footprint: true, meshing: true))
        #expect(PreviewSweepRule.verdict(of: rung(1, footprint: 1_000_000_001), smallest: smallest) == .init(
            gpuFrame: true, cpuFrame: true, footprint: false, meshing: true))
        #expect(PreviewSweepRule.verdict(of: rung(1, mesh: 1_001), smallest: smallest) == .init(
            gpuFrame: true, cpuFrame: true, footprint: true, meshing: false))
        #expect(PreviewSweepRule.verdict(of: rung(1, cpu: 6, footprint: 1_000_000_000, mesh: 1_000), smallest: smallest).passes)
    }

    @Test func noRungMeetingTheRuleGivesNoCap() {
        #expect(PreviewSweepRule.capCandidate([rung(250_000, gpu: 9), rung(500_000, gpu: 9)]) == nil)
        #expect(PreviewSweepRule.capCandidate([]) == nil)
    }

    #if canImport(Darwin)
    @Test func theFootprintIsReadableAndGrowsWithAnAllocation() {
        let before = PreviewSweepFixtures.footprint
        #expect(before > 1_000_000)
        var block = [UInt8](repeating: 1, count: 64_000_000)
        block[block.count - 1] = 2  // touch the pages so they are resident
        let after = PreviewSweepFixtures.footprint
        #expect(after - before > 32_000_000 && block.last == 2, "\(before) → \(after)")
    }
    #endif
}
