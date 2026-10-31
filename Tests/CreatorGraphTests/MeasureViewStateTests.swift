import CreatorGeometry
import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// Kept measurements live in the view state like the section: an optional key, no format bump, no edit.
@MainActor
struct MeasureViewStateTests {
    private let node = NodeID()

    private func roundTrip(_ state: ViewState) throws -> ViewState {
        try JSONDecoder().decode(ViewState.self, from: JSONEncoder().encode(state))
    }

    private var facePick: FacePick {
        FacePick(tags: [TopoTag(node: node, item: 0, role: .endCap)], normal: Vector3(0, 0, 1), centroid: Vector3(1, 2, 3))
    }

    private var edgePick: EdgePick {
        EdgePick(key: EdgeKey([TopoTag(node: node, item: 0, role: .endCap)], [TopoTag(node: node, item: 0, role: .side(segment: 1))]),
                 matchCount: 1)
    }

    @Test func everyAnchorRoundTrips() throws {
        let anchors: [MeasureAnchor] = [
            .face(facePick), .edge(edgePick), .corner(edgePick, .start), .corner(edgePick, .centre),
            .sectionEdge(SectionEdgeAnchor(face: facePick, index: 1, count: 3, midpoint: Vector3(4, 5, 6))),
            .meshSectionEdge(Vector3(7, 8, 9)), .meshPoint(Vector3(1, 1, 1)),
        ]
        let kept = anchors.map { KeptMeasurement(anchors: [$0]) } + [KeptMeasurement(anchors: [anchors[0], anchors[1]])]
        let decoded = try roundTrip(ViewState(measurements: kept))
        #expect(decoded.measurements == kept)
    }

    @Test func noMeasurementsWritesNoKey() throws {
        let json = try #require(String(bytes: JSONEncoder().encode(ViewState()), encoding: .utf8))
        #expect(!json.contains("measurements"))
    }

    @Test func anOlderFileReadsNone() throws {
        let decoded = try JSONDecoder().decode(ViewState.self, from: Data(#"{"dock":"left"}"#.utf8))
        #expect(decoded.measurements.isEmpty)
    }

    @Test func aDamagedMeasurementIsDroppedAlone() throws {
        let good1 = KeptMeasurement(anchors: [.meshPoint(Vector3(1, 2, 3))])
        let good2 = KeptMeasurement(anchors: [.meshSectionEdge(Vector3(4, 5, 6))])
        let encoder = JSONEncoder()
        let first = try #require(String(bytes: encoder.encode(good1), encoding: .utf8))
        let last = try #require(String(bytes: encoder.encode(good2), encoding: .utf8))
        let point = try #require(String(bytes: encoder.encode(MeasureAnchor.meshPoint(.zero)), encoding: .utf8))
        let id = UUID().uuidString
        let damaged = [
            #"{"id":"\#(id)","anchors":[{"bogus":1}]}"#,
            #"{"id":"\#(id)","anchors":[]}"#,
            #"{"id":"\#(id)","anchors":[\#(point),\#(point),\#(point)]}"#,
        ]
        for bad in damaged {
            let json = #"{"measurements":[\#(first),\#(bad),\#(last)]}"#
            let decoded = try JSONDecoder().decode(ViewState.self, from: Data(json.utf8))
            #expect(decoded.measurements == [good1, good2], "\(bad)")
        }
    }

    @Test func settingMeasurementsIsNoEdit() throws {
        let document = DocumentModel(file: GraphFile(graph: graph([makeNode(ConstantNode.self)])), registry: testRegistry,
                                     kernel: FakeKernel())
        let contentBefore = document.content
        let kept = [KeptMeasurement(anchors: [.face(facePick)])]
        document.measurements = kept
        #expect(document.viewState.measurements == kept)
        #expect(document.content == contentBefore)
        #expect(!document.canUndo)
        #expect(document.undoName == nil)
        let reopened = try DocumentModel(data: try document.fileData(), registry: testRegistry, kernel: FakeKernel())
        #expect(reopened.measurements == kept)
    }

    @Test func newDocumentHasNone() {
        let document = DocumentModel(file: GraphFile(graph: graph([])), registry: testRegistry, kernel: FakeKernel())
        #expect(document.measurements.isEmpty)
    }
}
