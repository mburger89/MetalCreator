import CreatorGeometry
import Testing
@testable import CreatorImplicit

struct TriangleMeshTests {
    @Test func aCubeHasTheVolumeAreaAndBoundsOfACube() throws {
        let cube = MeshFixtures.cube
        #expect(abs(cube.signedVolume - 1) < 1e-9)
        #expect(abs(cube.surfaceArea - 6) < 1e-9)
        #expect(cube.bounds == BoundingBox(min: .zero, max: Vector3(1, 1, 1)))
        #expect(cube.vertexCount == 8 && cube.triangleCount == 12)
    }

    @Test func aTetrahedronIsWoundOutwards() {
        // Edge 2√2, volume 8/3.
        #expect(abs(MeshFixtures.tetrahedron.signedVolume - 8.0 / 3) < 1e-6)
    }

    @Test func aMeshCostsSixteenPerVertexAndTwelvePerTriangle() {
        #expect(MeshFixtures.cube.estimatedBytes == 16 * 8 + 12 * 12)
        #expect(MeshFixtures.cube.triangleCount == 12)
    }

    @Test func eachMeshHasItsOwnIDAndCopiesShareIt() {
        let a = MeshFixtures.cube
        #expect(a.id == a.id && a.id != MeshFixtures.tetrahedron.id)
        #expect(a.highlighting([MeshHighlight(triangles: [0], label: "thin")]).id == a.id)
        #expect(a.highlighting([MeshHighlight(triangles: [0], label: "thin")]).highlights.count == 1)
    }

    @Test func anEmptyMeshHasNoBounds() {
        let empty = TriangleMesh(positions: [], triangles: [])
        #expect(empty.bounds == nil && empty.signedVolume == 0 && empty.triangleCount == 0)
    }
}
