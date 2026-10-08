import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

struct EdgePickFileTests {
    /// Fixed node identities, so two calls give equal picks.
    let plate = NodeID()
    let flangeNode = NodeID()

    func samplePicks() -> [EdgePick] {
        let top = TopoTag(node: plate, item: 0, role: .endCap)
        let side = TopoTag(node: plate, item: 0, role: .side(segment: 2))
        let flange = TopoTag(node: flangeNode, item: 0, role: .side(segment: 1))
        return [EdgePick(key: EdgeKey([top], [side, flange]), matchCount: 2, ordinals: [1]),
                EdgePick(key: EdgeKey([top], [side]), matchCount: 1),
        ]
    }

    @Test func edgePicksRoundTripThroughAFile() throws {
        let rule = makeNode(ConstantNode.self, ["picks": .edgePicks(samplePicks())])
        let file = GraphFile(graph: graph([rule]))
        let decoded = try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
        #expect(decoded == file)
        #expect(decoded.graph.nodes[rule.id]?.inputValues["picks"] == .edgePicks(samplePicks()))
    }

    @Test func savedFilesCarryFormatVersionTwo() throws {
        #expect(GraphFile.currentFormatVersion == 2)
        let text = try #require(String(bytes: try GraphFileIO.encode(GraphFile()), encoding: .utf8))
        #expect(text.contains(#""formatVersion" : 2"#))
    }

    @Test func versionOneFilesStillLoad() throws {
        let id = NodeID()
        let json = """
        {"formatVersion": 1, "graph": {"nodes": [{"id": "\(id.rawValue.uuidString)", "typeID": "test.constant",
        "typeVersion": 1, "name": "Constant", "inputValues": {"value": {"type": "number", "value": 3}},
        "position": {"x": 0, "y": 0}, "isOutput": false}]}}
        """
        let file = try GraphFileIO.decode(Data(json.utf8), registry: testRegistry)
        #expect(file.graph.nodes[id]?.inputValues["value"] == .number(3))
    }

    @Test func edgePicksAreASettingWithNoRuntimeValue() {
        #expect(Scalar(.edgePicks(samplePicks())) == nil)
        #expect(ConstantValue.edgePicks(samplePicks()).isFinite)
    }
}
