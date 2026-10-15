import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// The implicit benchmarks' fixtures, checked in the default run (the benchmarks themselves are skipped): the sheet builds, meshes to a
/// closed surface at a small size with the volume a gyroid sheet has, and a thickness edit changes it.
@MainActor
struct ImplicitBenchFixturesTests {
    /// A 20 mm cube with one 20 mm gyroid cell and a 1 mm wall, at 0.5 mm.
    func small(wall: Double = 1) -> ImplicitBenchFixtures.Sheet {
        ImplicitBenchFixtures.sheet(side: 20, cell: 20, wall: wall, exportResolution: 0.5)
    }

    func volume(_ report: EvaluationReport, _ output: Node) -> Double {
        if case .mesh(let payload)? = report.results[output.id]?.outputs?["mesh"]?.items.first, let mesh = payload as? TriangleMesh {
            mesh.signedVolume
        } else {
            0
        }
    }

    @Test func theSheetMeshesToAClosedSurfaceWithAGyroidsVolume() async throws {
        let sheet = small()
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
            .evaluate(sheet.graph, demand: [sheet.output.id], meshQuality: .export)
        guard case .mesh(let payload)? = report.results[sheet.output.id]?.outputs?["mesh"]?.items.first,
              let mesh = payload as? TriangleMesh else {
            Issue.record("no mesh: \(String(describing: report.results[sheet.output.id]?.state))")
            return
        }
        #expect(MeshTopology(mesh).isClosedManifold && mesh.signedVolume > 0)
        // A wall of 1 mm on a surface of 3.09 × 20² = 1,236 mm², less what the cube cuts off, in a cube of 8,000 mm³.
        #expect(mesh.signedVolume > 8_000 * 0.10 && mesh.signedVolume < 8_000 * 0.18, "volume \(mesh.signedVolume)")
    }

    @Test func aThicknessEditMakesAThickerSheetWithoutEvaluatingTheCubeAgain() async throws {
        let sheet = small()
        let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
        let first = try await evaluator.evaluate(sheet.graph, demand: [sheet.output.id], meshQuality: .export)
        var edited = sheet.graph
        edited.nodes[sheet.thickness.id]?.inputValues["thickness"] = .number(2)
        let second = try await evaluator.evaluate(edited, demand: [sheet.output.id], meshQuality: .export)
        #expect(volume(second, sheet.output) > volume(first, sheet.output) * 1.6)
        #expect(second.evaluatedNodes.count == 3, "the TPMS node, the Mesh and the Output ran again; the cube is cached")
    }

    @Test func theBenchmarksSheetIsOneGyroidCellOfAHundredMillimetres() {
        let sheet = ImplicitBenchFixtures.sheet()
        let node = sheet.graph.nodes[sheet.thickness.id]
        #expect(node?.inputValues["cell size"] == .number(100) && node?.inputValues["thickness"] == .number(3))
    }

    @Test func theSheetIsAnImplicitSolidFillingTheCube() async throws {
        let sheet = ImplicitBenchFixtures.sheet(side: 20, scale: 8, exportResolution: 0.5)
        let solid = try await ImplicitBenchFixtures.solid(of: sheet)
        let size = solid.bounds.size
        #expect(size.x <= 20.01 && size.y <= 20.01 && size.z <= 20.01 && size.x > 5)
    }

    #if canImport(Darwin) || canImport(Glibc)
    @Test func peakMemoryIsReadable() {
        #expect(ImplicitBenchFixtures.peakMemory > 1_000_000)
    }
    #endif
}
