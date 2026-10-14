import CreatorGeometry
import Testing
@testable import CreatorKernel

/// A solid that is only a mesh on display (implicit spec §5.1).
struct DisplayMeshStorageTests {
    let mesh = DisplayMesh(
        positions: [Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(0, 3, 0), Vector3(0, 0, 2)],
        normals: [Vector3](repeating: .unitZ, count: 4), indices: [0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3],
        triangleFaces: [FaceID](repeating: FaceID(0), count: 4), edgePolylines: [:])

    @Test func theSolidHasBoundsAroundTheVerticesAndNoTopology() {
        let solid = Solid(displaying: mesh)
        #expect(solid.bounds == BoundingBox(min: .zero, max: Vector3(4, 3, 2)))
        #expect(solid.topology.faces.isEmpty && solid.topology.edges.isEmpty)
        #expect(solid.estimatedBytes == solid.storage.estimatedBytes)
    }

    @Test func theMeshComesBack() {
        let solid = Solid(displaying: mesh)
        #expect(solid.displayedMesh?.indices == mesh.indices && solid.displayedMesh?.positions == mesh.positions)
    }

    @Test func aSolidFromAKernelIsNotAMeshOnDisplay() async throws {
        let kernel = FakeKernel()
        let box = try await kernel.extrude(.rectangle(width: 2, height: 2, plane: .xy), distance: 2, mode: .oneSided,
                                           tag: NodeTag(node: NodeID(), item: 0))
        #expect(box.displayedMesh == nil)
    }

    @Test func aMeshWithNoVerticesHasZeroBounds() {
        let empty = Solid(displaying: DisplayMesh(positions: [], normals: [], indices: [], triangleFaces: [], edgePolylines: [:]))
        #expect(empty.bounds == BoundingBox(min: .zero, max: .zero))
    }

    @Test func eachMeshOnDisplayIsItsOwnSolid() {
        #expect(Solid(displaying: mesh) !== Solid(displaying: mesh))
    }
}
