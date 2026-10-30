import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp

/// The section cap of a mesh part (a display-only solid): sliced from the display mesh, and sliced again when a finer pass replaces it.
@MainActor
struct SectionCapMeshTests {
    @Test func aMeshPartIsSlicedAndRefinedMeshesReslice() async throws {
        var builder = GraphBuilder()
        let sphere = builder.add(ImplicitSphereNode.self, ["radius": .number(6)])
        let mesh = builder.add(MeshNode.self, ["preview resolution": .number(0.03)])
        let output = builder.add(OutputNode.self)
        builder.wire(sphere, "implicit", to: mesh, "implicit")
        builder.wire(mesh, "mesh", to: output, "mesh")
        let app = await makeApp(builder.graph)
        app.setSection(true)
        await app.settle()
        // Taken together: what is shown and the cap cut from it (a loaded machine may refine before this point).
        let firstSolid = try #require(app.viewport.items.first).solid
        let coarse = try #require(app.viewport.section)
        #expect(coarse.caps.count == 1 && !coarse.caps[0].triangles.isEmpty)
        // On a machine so loaded that refinement ended before the first cap was cut, there is no coarse cap to compare with.
        let wasRefining = app.meshRefinement.badge?.isRefining == true
        let refinements = app.meshRefinement.revision
        await app.meshRefinement.waitForRefinement()
        await app.settle()
        let fine = try #require(app.viewport.section)
        let finalMesh = try #require(app.viewport.items.first?.solid.displayedMesh)
        let direct = MeshSlicer.slice(positions: finalMesh.positions, triangles: finalMesh.indices, plane: fine.plane)
        #expect(fine.caps[0].triangles.count == direct.regions.reduce(0) { $0 + $1.triangles.count },
                "the cap is cut from the mesh the viewport shows now")
        if wasRefining {
            #expect(app.meshRefinement.revision > refinements && app.viewport.items.first?.solid !== firstSolid,
                    "a refinement replaced the mesh")
            #expect(fine.generation != coarse.generation, "and the finer mesh was cut again")
        }
    }
}
