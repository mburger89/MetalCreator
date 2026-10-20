import CreatorGraph
import Testing
@testable import CreatorImplicit

/// The meshes the tools make from another (`derived`, `checked`).
struct TriangleMeshDerivedTests {
    @Test func aDerivedMeshIsANewMeshWithoutASourceOrHighlights() {
        let base = TriangleMesh(positions: MeshFixtures.cube.positions, triangles: MeshFixtures.cube.triangles, resolution: 0.5,
                                quality: .export, highlights: [MeshHighlight(triangles: [0], label: "x")], meshingSeconds: 2)
        let made = base.derived(positions: MeshFixtures.tetrahedron.positions, triangles: MeshFixtures.tetrahedron.triangles,
                                facts: [PayloadFact("Decimated", "12 → 4 triangles")])
        #expect(made.id != base.id && made.source == nil && made.highlights.isEmpty)
        #expect(made.resolution == 0.5 && made.quality == .export && made.meshingSeconds == 2 && made.triangleCount == 4)
        #expect(made.inspectorFacts.map(\.label) == ["Triangles", "Resolution", "Meshing time", "Decimated", "Memory"])
    }

    @Test func aCheckedMeshKeepsTheGeometryAndGetsANewID() {
        let base = MeshFixtures.cube
        let flagged = base.checked(highlights: [MeshHighlight(triangles: [3, 4], label: "thin")],
                                   facts: [PayloadFact("Thinnest wall", "0.2 mm")])
        #expect(flagged.id != base.id && flagged.positions == base.positions && flagged.triangles == base.triangles)
        #expect(flagged.highlights.count == 1 && flagged.source == nil)
        #expect(flagged.inspectorFacts.contains(PayloadFact("Thinnest wall", "0.2 mm")))
        #expect(base.inspectorFacts.map(\.label) == ["Triangles", "Memory"], "a plain mesh shows no extra line")
    }
}
