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

    @Test func savedFilesCarryFormatVersionThree() throws {
        #expect(GraphFile.currentFormatVersion == 3)
        let text = try #require(String(bytes: try GraphFileIO.encode(GraphFile()), encoding: .utf8))
        #expect(text.contains(#""formatVersion" : 3"#))
    }

    @Test func versionTwoEdgePicksDecodeAsOuterWalls() throws {
        let id = NodeID()
        let json = """
        {"formatVersion": 2, "graph": {"nodes": [{"id": "\(id.rawValue.uuidString)", "typeID": "test.constant",
        "typeVersion": 1, "name": "Constant", "position": {"x": 0, "y": 0}, "isOutput": false,
        "inputValues": {"picks": {"type": "edgePicks", "value": [{"matchCount": 1, "key": {
          "first": [{"node": "\(plate.rawValue.uuidString)", "item": 0, "role": {"role": "endCap"}}],
          "second": [{"node": "\(plate.rawValue.uuidString)", "item": 0, "role": {"role": "side", "segment": 2}}]}}]}}}]}}
        """
        let file = try GraphFileIO.decode(Data(json.utf8), registry: testRegistry)
        let top = TopoTag(node: plate, item: 0, role: .endCap)
        let wall = TopoTag(node: plate, item: 0, role: .side(loop: 0, segment: 2))
        #expect(file.graph.nodes[id]?.inputValues["picks"] == .edgePicks([EdgePick(key: EdgeKey([top], [wall]), matchCount: 1)]))
    }

    @Test func holeWallPicksRoundTripThroughAFile() throws {
        let top = TopoTag(node: plate, item: 0, role: .endCap)
        let rim = TopoTag(node: plate, item: 0, role: .side(loop: 1, segment: 0))
        let rule = makeNode(ConstantNode.self, ["picks": .edgePicks([EdgePick(key: EdgeKey([top], [rim]), matchCount: 1)])])
        let data = try GraphFileIO.encode(GraphFile(graph: graph([rule])))
        #expect(try #require(String(bytes: data, encoding: .utf8)).contains(#""loop" : 1"#))
        let decoded = try GraphFileIO.decode(data, registry: testRegistry)
        #expect(decoded.graph.nodes[rule.id]?.inputValues == rule.inputValues)
    }

    @Test func outerWallPicksAreWrittenAsBefore() throws {
        let rule = makeNode(ConstantNode.self, ["picks": .edgePicks(samplePicks())])
        let text = try #require(String(bytes: try GraphFileIO.encode(GraphFile(graph: graph([rule]))), encoding: .utf8))
        #expect(!text.contains(#""loop""#))
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
