import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// The implicit benchmarks' fixtures, checked in the default run (the benchmarks themselves are skipped): the sheet builds, meshes to a
/// closed surface at a small size, and a thickness edit changes it.
@MainActor
struct ImplicitBenchFixturesTests {
    @Test func theSheetMeshesToAClosedSurface() async throws {
        let sheet = ImplicitBenchFixtures.sheet(side: 20, scale: 8, exportResolution: 0.5)
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
            .evaluate(sheet.graph, demand: [sheet.output.id], meshQuality: .export)
        guard case .mesh(let payload)? = report.results[sheet.output.id]?.outputs?["mesh"]?.items.first,
              let mesh = payload as? TriangleMesh else {
            Issue.record("no mesh: \(String(describing: report.results[sheet.output.id]?.state))")
            return
        }
        #expect(MeshTopology(mesh).isClosedManifold && mesh.signedVolume > 0)
        // The band between two levels of the noise holds a fraction of the cube's volume, never all of it.
        #expect(mesh.signedVolume > 100 && mesh.signedVolume < 8_000 * 0.5)
    }

    @Test func aThicknessEditMakesAThickerSheetWithoutEvaluatingTheNoiseAgain() async throws {
        let sheet = ImplicitBenchFixtures.sheet(side: 20, scale: 8, exportResolution: 0.5)
        let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
        let first = try await evaluator.evaluate(sheet.graph, demand: [sheet.output.id], meshQuality: .export)
        var edited = sheet.graph
        edited.nodes[sheet.levels.id]?.inputValues["step"] = .number(-0.2)
        let second = try await evaluator.evaluate(edited, demand: [sheet.output.id], meshQuality: .export)
        func volume(_ report: EvaluationReport) -> Double {
            if case .mesh(let payload)? = report.results[sheet.output.id]?.outputs?["mesh"]?.items.first,
               let mesh = payload as? TriangleMesh { mesh.signedVolume } else { 0 }
        }
        #expect(volume(second) > volume(first) * 1.2)
        // The noise and the cube are cached; the levels, the isosurfaces, the cut, the Mesh and the Output ran again.
        #expect(second.evaluatedNodes.count == 5)
    }

    #if canImport(Darwin) || canImport(Glibc)
    @Test func peakMemoryIsReadable() {
        #expect(ImplicitBenchFixtures.peakMemory > 1_000_000)
    }
    #endif
}
