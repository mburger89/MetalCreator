import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import CreatorViewport
import Testing
@testable import CreatorApp

/// A check's highlighted triangles reach the viewport as faces drawn in the warning colour (implicit spec §5.1).
@MainActor
struct CheckHighlightSceneTests {
    func output(_ mesh: TriangleMesh) -> [SceneItem] {
        let node = BuiltInNodes.registry.makeNode(MeshNode.typeID)
        return SceneBuilder.items(of: node, outputs: ["mesh": .one(.mesh(mesh))], isGhost: false, graph: Graph())
    }

    @Test func flaggedTrianglesAreTheirOwnFaceInTheDisplayMesh() {
        let cube = CheckCube.mesh.checked(highlights: [MeshHighlight(triangles: [2, 3, 99], label: "thin")], facts: [])
        let faces = cube.displayMesh.triangleFaces.map(\.rawValue)
        #expect(faces == [0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0], "an index past the end is ignored")
        #expect(CheckCube.mesh.displayMesh.triangleFaces.allSatisfy { $0 == FaceID(0) })
    }

    @Test func aFlaggedMeshItemCarriesTheWarningFace() throws {
        let flagged = CheckCube.mesh.checked(highlights: [MeshHighlight(triangles: [1], label: "thin")], facts: [])
        #expect(try #require(output(flagged).first).item.warningFaces == [TriangleMesh.warningFace])
        #expect(try #require(output(CheckCube.mesh).first).item.warningFaces.isEmpty)
        let empty = CheckCube.mesh.checked(highlights: [MeshHighlight(triangles: [], label: "none")], facts: [])
        #expect(try #require(output(empty).first).item.warningFaces.isEmpty, "a highlight with no triangles marks nothing")
    }

    @Test func twoItemsThatDifferOnlyInTheirWarningFacesDrawDifferently() async throws {
        let solid = try await FakeKernel().extrude(.rectangle(width: 1, height: 1, plane: .xy), distance: 1, mode: .oneSided,
                                                   tag: NodeTag(node: NodeID(), item: 0))
        let plain = ViewportItem(solid: solid), flagged = ViewportItem(solid: solid, warningFaces: [FaceID(1)])
        #expect(plain.drawsTheSame(as: plain) && !plain.drawsTheSame(as: flagged))
    }
}

/// A unit cube of twelve triangles, wound counter-clockwise seen from outside.
private enum CheckCube {
    static let mesh = TriangleMesh(
        positions: [
            SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(1, 1, 0), SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(0, 0, 1), SIMD3<Float>(1, 0, 1), SIMD3<Float>(1, 1, 1), SIMD3<Float>(0, 1, 1),
        ],
        triangles: [
            0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7, 0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5, 2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7,
        ])
}
