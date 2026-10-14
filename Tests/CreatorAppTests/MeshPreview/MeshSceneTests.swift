import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// Meshes in the scene (implicit spec §5.1): the display mesh, the display solid, and what the scene builder does with a mesh result.
struct MeshSceneTests {
    func tetrahedron(id: UUID = UUID(), source: MeshSource? = nil) -> TriangleMesh {
        TriangleMesh(positions: MeshFixture.tetrahedron.positions, triangles: MeshFixture.tetrahedron.triangles, resolution: 0.5,
                     source: source, id: id)
    }

    @Test func theDisplayMeshAveragesTheFacesWhenTheMesherGaveNoNormals() {
        let display = tetrahedron().displayMesh
        #expect(display.positions.count == 4 && display.indices.count == 12 && display.triangleFaces.count == 4)
        #expect(display.triangleFaces.allSatisfy { $0 == FaceID(0) } && display.edgePolylines.isEmpty)
        // A regular tetrahedron about the origin: each vertex normal points away from the centre.
        for (position, normal) in zip(display.positions, display.normals) {
            #expect(abs(normal.length - 1) < 1e-9 && normal.dot(position) > 0)
        }
    }

    @Test func theMeshersNormalsAreUsed() {
        var mesh = tetrahedron()
        mesh.normals = [SIMD3<Float>](repeating: SIMD3(0, 0, 1), count: 4)
        #expect(mesh.displayMesh.normals.allSatisfy { $0 == Vector3.unitZ })
    }

    @Test func aVertexWithADegenerateGradientIsShadedWithItsFacesNormal() {
        var mesh = tetrahedron()
        mesh.normals = [SIMD3<Float>(0, 0, 1), .zero, SIMD3<Float>(0, 0, 1), SIMD3<Float>(.nan, 0, 0)]
        let shading = mesh.displayMesh.normals
        #expect(shading[0] == Vector3.unitZ && shading[2] == Vector3.unitZ, "a good normal is kept")
        let fallback = tetrahedron().displayMesh.normals
        for index in [1, 3] {
            #expect(abs(shading[index].length - 1) < 1e-9 && shading[index] == fallback[index], "vertex \(index) takes the faces' average")
        }
    }

    @Test func aMeshKeepsOneDisplaySolidWhileItIsShown() {
        let solids = MeshSolids()
        let mesh = tetrahedron()
        let first = solids.solid(for: mesh)
        #expect(solids.solid(for: mesh) === first)
        #expect(solids.solid(for: tetrahedron()) !== first, "another mesh, another solid")
        solids.keep([mesh.id])
        #expect(solids.count == 1 && solids.solid(for: mesh) === first)
        solids.keep([])
        #expect(solids.count == 0)
    }

    @Test func aMeshResultMakesAnItemWithTheNodeAsItsSource() {
        let node = BuiltInNodes.registry.makeNode(MeshNode.typeID)
        let mesh = tetrahedron()
        let scene = MeshScene(solids: MeshSolids())
        let items = SceneBuilder.items(of: node, outputs: ["mesh": .one(.mesh(mesh))], isGhost: false, graph: Graph(), meshes: scene)
        #expect(items.count == 1 && items[0].source == Endpoint(node: node.id, socket: "mesh"))
        #expect(items[0].item.solid.displayedMesh?.indices == mesh.displayMesh.indices)
        #expect(!items[0].item.isGhost)
    }

    @Test func aRefinementReplacesTheMeshItShows() {
        let node = BuiltInNodes.registry.makeNode(MeshNode.typeID)
        let base = tetrahedron(), finer = tetrahedron()
        var scene = MeshScene(solids: MeshSolids())
        scene.refined = [base.id: finer]
        let items = SceneBuilder.items(of: node, outputs: ["mesh": .one(.mesh(base))], isGhost: false, graph: Graph(), meshes: scene)
        let shown = scene.solids.solid(for: finer)
        #expect(items[0].item.solid === shown)
    }

    @Test func aStaleMeshIsAGhostLikeAStaleSolid() {
        let node = BuiltInNodes.registry.makeNode(MeshNode.typeID)
        let mesh = tetrahedron()
        let options = SceneBuilder.Options(selection: [], showsGuides: false, meshes: MeshScene(solids: MeshSolids()))
        let items = SceneBuilder.scene(shown: [node.id], graph: Graph(nodes: [node.id: node]), results: [:],
                                       lastGood: [node.id: ["mesh": .one(.mesh(mesh))]], options: options)
        #expect(items.count == 1 && items[0].item.isGhost)
    }

    @Test func onlyCurrentMeshesWithASourceAreForRefinement() {
        let node = BuiltInNodes.registry.makeNode(MeshNode.typeID)
        let source = MeshSource(solid: .sphere(radius: 3), target: .automatic)
        let refinable = tetrahedron(source: source), plain = tetrahedron()
        let current = NodeResult(state: .ok(duration: .zero), outputs: ["mesh": .list([.mesh(refinable), .mesh(plain)])])
        #expect(SceneBuilder.previewMeshes(shown: [node.id], results: [node.id: current]).map(\.id) == [refinable.id])
        let failed = NodeResult(state: .error("e"), outputs: ["mesh": .one(.mesh(refinable))])
        #expect(SceneBuilder.previewMeshes(shown: [node.id], results: [node.id: failed]).isEmpty)
        #expect(SceneBuilder.previewMeshes(shown: [node.id], results: [:]).isEmpty)
    }
}
