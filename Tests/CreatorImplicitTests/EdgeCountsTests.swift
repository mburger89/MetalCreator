import Testing
@testable import CreatorImplicit

/// A unit cube, outward counter-clockwise, 8 vertices and 12 triangles.
func unitBoxMesh() -> TriangleMesh {
    let positions: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0], [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]]
    let triangles: [UInt32] = [0, 3, 2, 0, 2, 1, 4, 5, 6, 4, 6, 7, 0, 1, 5, 0, 5, 4,
                               3, 7, 6, 3, 6, 2, 0, 4, 7, 0, 7, 3, 1, 2, 6, 1, 6, 5,
                              ]
    return TriangleMesh(positions: positions, triangles: triangles)
}

@Suite struct EdgeCountsTests {
    @Test func aBoxIsClosed() {
        let counts = EdgeCounts(unitBoxMesh())
        #expect(counts.open == 0 && counts.overfull == 0 && counts.flipped == 0)
        #expect(counts.isClosed)
    }

    @Test func aMissingFaceCountsThreeOpenEdges() {
        var mesh = unitBoxMesh()
        mesh.triangles.removeLast(3)
        // The right face's second triangle is gone: its four edges leave the face open along three of them.
        let counts = EdgeCounts(mesh)
        #expect(counts.open == 3)
        #expect(!counts.isClosed)
    }

    @Test func aFlippedFaceCountsThree() {
        var mesh = unitBoxMesh()
        let last = mesh.triangles.count - 3
        mesh.triangles.swapAt(last + 1, last + 2)
        let counts = EdgeCounts(mesh)
        #expect(counts.flipped == 3)
        #expect(counts.open == 0)
        #expect(!counts.isClosed)
    }

    @Test func threeFacesOnAnEdgeCountOneOverfull() {
        var mesh = unitBoxMesh()
        // A third face on the bottom's diagonal edge 0-2.
        mesh.positions.append([2, 2, 2])
        mesh.triangles += [0, 2, 8]
        let counts = EdgeCounts(mesh)
        #expect(counts.overfull == 1)
        #expect(!counts.isClosed)
    }

    @Test func agreesWithMeshTopologyOnTheseMeshes() {
        var missing = unitBoxMesh()
        missing.triangles.removeLast(3)
        var flipped = unitBoxMesh()
        flipped.triangles.swapAt(1, 2)
        var overfull = unitBoxMesh()
        overfull.positions.append([2, 2, 2])
        overfull.triangles += [0, 2, 8]
        for mesh in [unitBoxMesh(), missing, flipped, overfull] {
            let counts = EdgeCounts(mesh)
            let topology = MeshTopology(mesh)
            #expect(counts.open == topology.openEdgeCount)
            #expect(counts.overfull == topology.overfullEdgeCount)
            #expect(counts.flipped == topology.inconsistentEdgeCount)
        }
    }
}
