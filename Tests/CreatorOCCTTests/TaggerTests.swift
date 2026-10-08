import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

struct TaggerTests {
    let tag = NodeTag(node: NodeID(), item: 0)

    func raw(faces: Int, edges: [[Int]] = []) -> OCCTRawTopology {
        OCCTRawTopology(
            faces: (0..<faces).map { _ in .init(kind: .plane, normal: .unitZ, area: 1, centroid: .zero) },
            edges: edges.map { .init(kind: .line, direction: .unitX, length: 1, midpoint: .zero, convexity: .convex, faces: $0) }
        )
    }

    @Test func taggerFallsBackToUnnamed() {
        let topology = OCCTTagger.topology(raw: raw(faces: 2), history: [], inputs: [], tag: tag)
        #expect(topology.faces.map(\.tags) == [[TopoTag(tag, .unnamed(face: 0))], [TopoTag(tag, .unnamed(face: 1))]])
    }

    @Test func capsAndSegmentsBecomeRoles() {
        let history = [
            OCCTHistoryRecord(outFace: 0, kind: .startCap, operand: 0, index: 0),
            OCCTHistoryRecord(outFace: 1, kind: .endCap, operand: 0, index: 0),
            OCCTHistoryRecord(outFace: 2, kind: .segment, operand: 0, index: 3),
        ]
        let topology = OCCTTagger.topology(raw: raw(faces: 3), history: history, inputs: [], tag: tag)
        #expect(topology.faces[0].tags == [TopoTag(tag, .startCap)])
        #expect(topology.faces[1].tags == [TopoTag(tag, .endCap)])
        #expect(topology.faces[2].tags == [TopoTag(tag, .side(segment: 3))])
    }

    @Test func segmentRecordOperandsAreProfileLoops() {
        let history = [
            OCCTHistoryRecord(outFace: 0, kind: .segment, operand: 0, index: 1),
            OCCTHistoryRecord(outFace: 1, kind: .segment, operand: 2, index: 1),
        ]
        let topology = OCCTTagger.topology(raw: raw(faces: 2), history: history, inputs: [], tag: tag)
        #expect(topology.faces[0].tags == [TopoTag(tag, .side(segment: 1))])
        #expect(topology.faces[1].tags == [TopoTag(tag, .side(loop: 2, segment: 1))])
    }

    @Test func faceRecordsCarryInputTagsAndMergeUnions() {
        let a = TopoTag(node: NodeID(), item: 0, role: .endCap)
        let b = TopoTag(node: NodeID(), item: 1, role: .side(segment: 0))
        let inputA = Topology(faces: [FaceInfo(id: FaceID(0), kind: .plane, normal: nil, area: 1, centroid: .zero, tags: [a])], edges: [])
        let inputB = Topology(faces: [FaceInfo(id: FaceID(0), kind: .plane, normal: nil, area: 1, centroid: .zero, tags: [b])], edges: [])
        let history = [
            OCCTHistoryRecord(outFace: 0, kind: .face, operand: 0, index: 0),
            OCCTHistoryRecord(outFace: 0, kind: .face, operand: 1, index: 0),
        ]
        let topology = OCCTTagger.topology(raw: raw(faces: 1), history: history, inputs: [inputA, inputB], tag: tag)
        #expect(topology.faces[0].tags == [a, b])
    }

    @Test func edgeRecordsBecomeBlendsKeyedByTheInputEdge() throws {
        let top = TopoTag(node: NodeID(), item: 0, role: .endCap)
        let side = TopoTag(node: NodeID(), item: 0, role: .side(segment: 1))
        let input = Topology(
            faces: [FaceInfo(id: FaceID(0), kind: .plane, normal: nil, area: 1, centroid: .zero, tags: [top]),
                    FaceInfo(id: FaceID(1), kind: .plane, normal: nil, area: 1, centroid: .zero, tags: [side]),
            ],
            edges: [EdgeInfo(id: EdgeID(0), kind: .line, direction: nil, length: 1, midpoint: .zero, convexity: .convex,
                             faces: [FaceID(0), FaceID(1)]),
            ]
        )
        let history = [OCCTHistoryRecord(outFace: 0, kind: .edge, operand: 0, index: 0)]
        let topology = OCCTTagger.topology(raw: raw(faces: 1), history: history, inputs: [input], tag: tag)
        #expect(topology.faces[0].tags == [TopoTag(tag, .blend(sourceEdge: EdgeKey([top], [side])))])
    }

    @Test func edgesMapToFaceIDsAndSeams() {
        let topology = OCCTTagger.topology(raw: raw(faces: 2, edges: [[0, 1], [1, 1], []]), history: [], inputs: [], tag: tag)
        #expect(topology.edges[0].faces == [FaceID(0), FaceID(1)])
        #expect(topology.edges[1].isSeam)
        #expect(topology.edges[2].faces.isEmpty)
        #expect(topology.edges.map(\.id) == [EdgeID(0), EdgeID(1), EdgeID(2)])
    }

    @Test func outOfRangeRecordsAreIgnored() {
        let history = [OCCTHistoryRecord(outFace: 9, kind: .startCap, operand: 0, index: 0),
                       OCCTHistoryRecord(outFace: 0, kind: .face, operand: 5, index: 0),
        ]
        let topology = OCCTTagger.topology(raw: raw(faces: 1), history: history, inputs: [], tag: tag)
        #expect(topology.faces[0].tags == [TopoTag(tag, .unnamed(face: 0))])
    }
}
