import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Testing
@testable import CreatorNodes

/// Check Trapped Volumes (implicit spec §3.6): the highlight, the exact warning and the label on a preview.
struct CheckTrappedVolumesNodeTests {
    /// A ball with a sealed cavity, meshed by the Mesh node, then checked.
    func checked(_ h: inout Harness) -> (mesh: Node, check: Node) {
        // Radii 3 and 1.5 as a list: the ball, then the cavity cut from it.
        let radii = h.add(SeriesNode.self, ["start": .number(3), "step": .number(-1.5), "count": .integer(2)])
        let spheres = h.add(ImplicitSphereNode.self)
        let subtract = h.add(ImplicitSubtractNode.self)
        let mesh = h.add(MeshNode.self, ["export resolution": .number(0.2), "preview resolution": .number(0.2)])
        let check = h.add(CheckTrappedVolumesNode.self)
        h.wire(radii, "values", to: spheres, "radius")
        h.wire(spheres, "implicit", to: subtract, "shapes")
        h.wire(subtract, "implicit", to: mesh, "implicit")
        h.wire(mesh, "mesh", to: check, "mesh")
        return (mesh, check)
    }

    @Test func aSealedCavityIsHighlightedAndWarnedAboutInTheSpecsWords() async throws {
        var h = Harness()
        let (mesh, check) = checked(&h)
        let report = try await h.runForExport([check])
        let made = try #require(report.triangleMesh(check)), source = try #require(report.triangleMesh(mesh))
        let highlight = try #require(made.highlights.first)
        #expect(made.highlights.count == 1 && !highlight.triangles.isEmpty && highlight.label == "Enclosed voids")
        #expect(made.positions == source.positions && made.id != source.id)
        #expect(report.warning(check) == "1 enclosed void can't drain.")
        #expect(made.inspectorFacts.contains(PayloadFact("Enclosed voids", "1")))
    }

    @Test func aPreviewSaysItIsApproximate() async throws {
        var h = Harness()
        let (_, check) = checked(&h)
        let message = try #require(try await h.run([check]).warning(check))
        #expect(message == "1 enclosed void can't drain (approximate: preview resolution).", "\(message)")
    }

    @Test func aSolidBallHasNothingToReport() async throws {
        var h = Harness()
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(3)])
        let mesh = h.add(MeshNode.self, ["preview resolution": .number(0.3)])
        let check = h.add(CheckTrappedVolumesNode.self)
        h.wire(sphere, "implicit", to: mesh, "implicit")
        h.wire(mesh, "mesh", to: check, "mesh")
        let report = try await h.run([check])
        let made = try #require(report.triangleMesh(check))
        #expect(made.highlights.isEmpty && report.isOK(check))
        #expect(made.inspectorFacts.contains(PayloadFact("Enclosed voids", "0")))
        #expect(made.inspectorFacts.contains { $0.label == "Grid cell" && $0.value.hasSuffix(" mm") })
        #expect(report.warning(check) == nil, "a part this size has the usual cells")
    }

    @Test func aHugePartSaysItsCellsAreCoarseAndAUsualOneSaysNothing() {
        #expect(CheckWording.coarseGrid(cell: 0.5).isEmpty && CheckWording.coarseGrid(cell: 0.2).isEmpty)
        #expect(CheckWording.coarseGrid(cell: 3.1)
            == ["The part is large: the check's cells are 3.1 mm, so holes under 12.4 mm may not count as open."])
    }

    @Test func thePluralsAreTheSpecsWords() {
        #expect(CheckWording.voids(3, label: nil) == "3 enclosed voids can't drain.")
        #expect(CheckWording.voids(1, label: nil) == "1 enclosed void can't drain.")
        #expect(CheckWording.voids(2, label: "approximate: preview resolution")
            == "2 enclosed voids can't drain (approximate: preview resolution).")
    }
}
