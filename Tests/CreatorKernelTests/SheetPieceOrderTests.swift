import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// R6: the one ordering of a split sheet's pieces, shared by the kernel and the app.
struct SheetPieceOrderTests {
    let node = NodeID()

    func face(_ id: Int, role: TopoRole, at centroid: Vector3, area: Double = 1) -> FaceInfo {
        FaceInfo(id: FaceID(id), kind: .plane, normal: .unitZ, area: area, centroid: centroid,
                 tags: [TopoTag(node: node, item: 0, role: role)])
    }

    @Test func ordersByKeyThenCentroidWhateverTheInputOrder() {
        let topology = Topology(faces: [
            face(0, role: .endCap, at: Vector3(5, 0, 0)),
            face(1, role: .endCap, at: Vector3(-5, 0, 0)),
            face(2, role: .startCap, at: Vector3(9, 0, 0)),
        ], edges: [])
        let groups = [[0], [1], [2]]
        let expected = SheetPieces.ordered(groups: groups, in: topology)
        #expect(SheetPieces.ordered(groups: groups.reversed(), in: topology) == expected)
        // Equal keys fall to the centroid: x = -5 before x = 5.
        let ends = expected.map { $0.map(\.rawValue) }.filter { $0 != [2] }
        #expect(ends == [[1], [0]])
    }

    @Test func aPieceKeepsItsFacesSorted() {
        let topology = Topology(faces: [face(0, role: .endCap, at: .zero), face(1, role: .endCap, at: .zero)], edges: [])
        #expect(SheetPieces.ordered(groups: [[1, 0]], in: topology).map { $0.map(\.rawValue) } == [[0, 1]])
    }
}
