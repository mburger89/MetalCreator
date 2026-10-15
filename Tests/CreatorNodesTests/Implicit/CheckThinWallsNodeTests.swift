import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Testing
@testable import CreatorNodes

/// Check Thin Walls (implicit spec §3.6): the highlight, the exact warning, and the label on a preview.
struct CheckThinWallsNodeTests {
    /// A hollow ball with a 0.3 mm wall as an implicit solid, meshed at the given quality by the Mesh node, then checked.
    func checked(_ h: inout Harness, minimum: Double = 0.4, exportResolution: Double = 0.1) -> (mesh: Node, check: Node) {
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(2)])
        let shell = h.add(ImplicitShellNode.self, ["thickness": .number(0.3)])
        let mesh = h.add(MeshNode.self, ["export resolution": .number(exportResolution)])
        let check = h.add(CheckThinWallsNode.self, ["minimum": .number(minimum)])
        h.wire(sphere, "implicit", to: shell, "implicit")
        h.wire(shell, "implicit", to: mesh, "implicit")
        h.wire(mesh, "mesh", to: check, "mesh")
        return (mesh, check)
    }

    @Test func aThinWallIsHighlightedAndWarnedAboutInTheSpecsWords() async throws {
        var h = Harness()
        let (mesh, check) = checked(&h)
        let report = try await h.runForExport([check])
        let made = try #require(report.triangleMesh(check)), source = try #require(report.triangleMesh(mesh))
        let highlight = try #require(made.highlights.first)
        #expect(made.highlights.count == 1 && !highlight.triangles.isEmpty && highlight.label == "Walls thinner than 0.4 mm")
        #expect(made.positions == source.positions && made.triangles == source.triangles && made.id != source.id)
        let message = try #require(report.warning(check))
        #expect(message.hasPrefix("Walls thinner than 0.4 mm in 1 place (thinnest 0.3"), "\(message)")
        #expect(message.hasSuffix(" mm).") && !message.contains("approximate"))
        #expect(made.inspectorFacts.contains { $0.label == "Thinnest wall" })
    }

    @Test func aPreviewSaysItIsApproximate() async throws {
        var h = Harness()
        let (_, check) = checked(&h)
        let report = try await h.run([check])
        let message = try #require(report.warning(check))
        #expect(message.hasSuffix(" mm) (approximate: preview resolution)."), "\(message)")
    }

    @Test func aWallAboveTheMinimumIsClear() async throws {
        var h = Harness()
        let (_, check) = checked(&h, minimum: 0.2)
        let report = try await h.runForExport([check])
        let made = try #require(report.triangleMesh(check))
        #expect(made.highlights.isEmpty && report.isOK(check))
        #expect(made.inspectorFacts.contains(PayloadFact("Thin walls", "none under 0.2 mm")))
    }

    @Test func theMinimumIsChecked() async throws {
        var h = Harness()
        let (_, small) = checked(&h, minimum: 0.001)
        let (_, nan) = checked(&h, minimum: .nan)
        let report = try await h.run([small, nan])
        #expect(report.error(small) == "“minimum” must be at least 0.01 mm.")
        #expect(report.error(nan) != nil)
    }

    @Test func thePluralsAndTheLabelAreTheSpecsWords() {
        #expect(CheckWording.thinWalls(minimum: 0.4, places: 3, thinnest: 0.21, label: nil)
            == "Walls thinner than 0.4 mm in 3 places (thinnest 0.21 mm).")
        #expect(CheckWording.thinWalls(minimum: 0.4, places: 1, thinnest: 0.21, label: nil)
            == "Walls thinner than 0.4 mm in 1 place (thinnest 0.21 mm).")
        #expect(CheckWording.thinWalls(minimum: 0.4, places: 1_200, thinnest: 0.21, label: "approximate: preview resolution")
            == "Walls thinner than 0.4 mm in 1,200 places (thinnest 0.21 mm) (approximate: preview resolution).")
    }
}
