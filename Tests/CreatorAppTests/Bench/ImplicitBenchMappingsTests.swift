import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif

/// The wrapped sheets of rows i-9 and i-10, checked small in the default run (the benchmarks themselves are skipped): they build, the
/// Cylindrical one meshes to a closed surface, and the Face-mapped one follows the cylinder's side.
@MainActor
struct ImplicitBenchMappingsTests {
    @Test func theCylindricalSheetMeshesToAClosedSurface() async throws {
        let sheet = ImplicitBenchFixtures.cylindricalSheet(radius: 14, height: 24, cell: 8, wall: 1.5, exportResolution: 0.8)
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
            .evaluate(sheet.graph, demand: [sheet.output.id], meshQuality: .export)
        guard case .mesh(let payload)? = report.results[sheet.output.id]?.outputs?["mesh"]?.items.first,
              let mesh = payload as? TriangleMesh else {
            Issue.record("no mesh: \(String(describing: report.results[sheet.output.id]?.state))")
            return
        }
        #expect(MeshTopology(mesh).isClosedManifold && mesh.signedVolume > 0)
        #expect(mesh.signedVolume < Double.pi * 14 * 14 * 24, "a sheet inside the post")
    }

    #if canImport(CreatorOCCT)
    @Test func theFaceSheetFollowsTheSideOfTheCylinder() async throws {
        let kernel = OCCTKernel()
        let sheet = try await ImplicitBenchFixtures.faceSheet(kernel: kernel, diameter: 24, height: 20, cell: 6, wall: 1.2,
                                                              exportResolution: 0.8)
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: kernel)
            .evaluate(sheet.graph, demand: [sheet.thickness.id])
        guard case .implicit(let reference)? = report.results[sheet.thickness.id]?.outputs?["implicit"]?.items.first,
              let solid = reference.solid else {
            Issue.record("no lattice: \(String(describing: report.results[sheet.thickness.id]?.state))")
            return
        }
        #expect(solid.description.contains(", face"), "\(solid.description)")
        #expect(solid.signedDistance(at: Vector3(0, 0, 10)).isFinite)
    }
    #endif
}
