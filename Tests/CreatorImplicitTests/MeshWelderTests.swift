import Testing
@testable import CreatorImplicit

/// Merging vertices that sit on one another, before a mesh becomes a solid.
struct MeshWelderTests {
    @Test func aMeshWithNothingToMergeKeepsItsShape() {
        let cube = MeshFixtures.cube
        let welded = MeshWelder.weld(positions: cube.positions, triangles: cube.triangles)
        let result = TriangleMesh(positions: welded.positions, triangles: welded.triangles)
        #expect(result.vertexCount == 8 && result.triangleCount == 12 && abs(result.signedVolume - 1) < 1e-9)
        #expect(MeshTopology(result).isClosedManifold)
    }

    @Test func aCubeWithItsVerticesDoubledPerFaceIsOneClosedCube() {
        let soup = MeshFixtures.cubeSoup
        let positions = soup.positions.map { SIMD3(Float($0.x), Float($0.y), Float($0.z)) }
        let welded = MeshWelder.weld(positions: positions, triangles: soup.indices)
        #expect(welded.positions.count == 8 && welded.triangles.count == 36)
        #expect(MeshTopology(TriangleMesh(positions: welded.positions, triangles: welded.triangles)).isClosedManifold)
    }

    @Test func aSliverCollapsedByTheWeldTakesItsTriangleAndKeepsTheMeshClosed() {
        // The sphere with one vertex split off by a hair: the two are one again, and nothing is left open.
        let sphere = MeshFixtures.sphereMesh(radius: 5, subdivisions: 2)
        var positions = sphere.positions
        var triangles = sphere.triangles
        positions.append(positions[0] + SIMD3(1e-8, 0, 0))
        let copy = UInt32(positions.count - 1)
        if let first = triangles.firstIndex(of: 0) { triangles[first] = copy }
        let welded = MeshWelder.weld(positions: positions, triangles: triangles)
        let result = TriangleMesh(positions: welded.positions, triangles: welded.triangles)
        #expect(result.vertexCount == sphere.vertexCount && result.triangleCount == sphere.triangleCount)
        #expect(MeshTopology(result).isClosedManifold)
    }

    @Test func aTriangleThatCollapsesIsDroppedAndUnusedVerticesGo() {
        let positions: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(1e-9, 0, 0), SIMD3(5, 5, 5)]
        let welded = MeshWelder.weld(positions: positions, triangles: [0, 1, 2, 0, 3, 1, 0, 1, 99])
        #expect(welded.triangles == [0, 1, 2] && welded.positions.count == 3)
    }

    @Test func aVertexThatIsNotAFinitePositionIsKeptUnmergedInsteadOfTrapping() {
        let positions: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(.nan, 0, 0), SIMD3(.nan, 0, 0),
                                         SIMD3(.infinity, 0, 0), SIMD3(1e30, 0, 0),
        ]
        let welded = MeshWelder.weld(positions: positions, triangles: [0, 1, 2, 0, 1, 3, 0, 1, 4, 0, 1, 5, 0, 1, 6])
        #expect(welded.triangles.count == 15 && welded.positions.count == 7, "two NaN vertices are two vertices, none merged")
        #expect(welded.positions.filter { !$0.x.isFinite }.count == 3)
    }
}
