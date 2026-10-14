import Testing
@testable import CreatorImplicit

struct MeshTopologyTests {
    @Test func aTetrahedronIsAClosedSphere() {
        let topology = MeshTopology(MeshFixtures.tetrahedron)
        #expect(topology.isClosedManifold)
        #expect(topology.usedVertexCount == 4 && topology.edgeCount == 6 && topology.triangleCount == 4)
        #expect(topology.eulerCharacteristic == 2)
    }

    @Test func aCubeIsAClosedSphere() {
        let topology = MeshTopology(MeshFixtures.cube)
        #expect(topology.isClosedManifold && topology.eulerCharacteristic == 2)
    }

    @Test func aMissingFaceLeavesOpenEdges() {
        var mesh = MeshFixtures.tetrahedron
        mesh.triangles.removeLast(3)
        let topology = MeshTopology(mesh)
        #expect(!topology.isClosedManifold && topology.openEdgeCount == 3)
    }

    @Test func aFlippedFaceIsInconsistent() {
        var mesh = MeshFixtures.tetrahedron
        mesh.triangles.swapAt(9, 10)
        let topology = MeshTopology(mesh)
        #expect(!topology.isClosedManifold && topology.inconsistentEdgeCount == 3)
    }

    @Test func aThirdFaceOnAnEdgeIsOverfull() {
        var mesh = MeshFixtures.tetrahedron
        mesh.positions.append(SIMD3<Float>(5, 5, 5))
        mesh.triangles += [0, 1, 4]
        #expect(MeshTopology(mesh).overfullEdgeCount >= 1)
        #expect(!MeshTopology(mesh).isClosedManifold)
    }

    @Test func aDegenerateTriangleIsCounted() {
        var mesh = MeshFixtures.tetrahedron
        mesh.triangles += [0, 0, 1]
        #expect(MeshTopology(mesh).degenerateTriangleCount == 1 && !MeshTopology(mesh).isClosedManifold)
    }

    @Test func twoCubesTouchingAtACornerShareANonManifoldVertex() {
        var positions = MeshFixtures.cube.positions
        var triangles = MeshFixtures.cube.triangles
        // A second cube whose corner (0, 0, 0) is the first cube's corner (1, 1, 1): they share vertex 6.
        let shift = SIMD3<Float>(1, 1, 1)
        let base = UInt32(positions.count)
        for (index, position) in MeshFixtures.cube.positions.enumerated() {
            positions.append(index == 0 ? positions[6] : position + shift)
        }
        triangles += MeshFixtures.cube.triangles.map { $0 == 0 ? 6 : $0 + base }
        let topology = MeshTopology(TriangleMesh(positions: positions, triangles: triangles))
        #expect(topology.openEdgeCount == 0 && topology.nonManifoldVertexCount == 1 && !topology.isClosedManifold)
    }
}
