import CreatorKernel
import Foundation
import Testing
@testable import CreatorGraph

/// Format 6 (7a: data trees). Trees are computed and never saved; the new saved thing is the Path Mapper's and Branch
/// by Path's text settings. Files of format 5 and earlier open exactly as they did.
struct TreeFileTests {
    func decode(_ json: String) throws -> GraphFile {
        try GraphFileIO.decode(Data(json.utf8), registry: testRegistry)
    }

    @Test func savedFilesAreFormatSix() throws {
        #expect(GraphFile.currentFormatVersion == 6)
        let text = try #require(String(bytes: try GraphFileIO.encode(GraphFile()), encoding: .utf8))
        #expect(text.contains(#""formatVersion" : 6"#))
    }

    @Test(arguments: [1, 2, 3, 4, 5])
    func aFileOfAnyEarlierFormatOpensUnchanged(_ version: Int) throws {
        let id = NodeID()
        let other = NodeID()
        let json = """
        {"formatVersion": \(version), "graph": {"nodes": [
        {"id": "\(id.rawValue.uuidString)", "typeID": "test.constant", "typeVersion": 1, "name": "Constant",
        "position": {"x": 3, "y": 4}, "isOutput": false, "inputValues": {"value": {"type": "number", "value": 2}}},
        {"id": "\(other.rawValue.uuidString)", "typeID": "test.add", "typeVersion": 1, "name": "Add",
        "position": {"x": 9, "y": 4}, "isOutput": true, "inputValues": {"b": {"type": "number", "value": 5}}}],
        "links": [{"from": {"node": "\(id.rawValue.uuidString)", "socket": "value"},
        "to": {"node": "\(other.rawValue.uuidString)", "socket": "a"}}]}}
        """
        let file = try decode(json)
        #expect(file.formatVersion == version, "a file keeps the version it was written with until it is saved")
        #expect(file.graph.nodes.count == 2)
        #expect(file.graph.nodes[id]?.inputValues["value"] == .number(2))
        #expect(file.graph.nodes[other]?.inputValues["b"] == .number(5))
        #expect(file.graph.nodes[other]?.isOutput == true)
        #expect(file.graph.links.count == 1)
        #expect(file.definitions.isEmpty && file.graph.stickies.isEmpty && file.graph.frames.isEmpty)
    }

    @Test func savingAnOldFileWritesFormatSixAndKeepsEverythingElse() throws {
        let id = NodeID()
        let json = """
        {"formatVersion": 5, "graph": {"nodes": [{"id": "\(id.rawValue.uuidString)", "typeID": "test.constant",
        "typeVersion": 1, "name": "Constant", "position": {"x": 0, "y": 0}, "isOutput": false,
        "inputValues": {"value": {"type": "number", "value": 2}}}]}}
        """
        let old = try decode(json)
        let saved = GraphFile(graph: old.graph, definitions: old.definitions, viewState: old.viewState)
        let reopened = try GraphFileIO.decode(try GraphFileIO.encode(saved), registry: testRegistry)
        #expect(reopened.formatVersion == 6)
        #expect(reopened.graph == old.graph)
    }

    @Test func theRuleAndPathSettingsRoundTripAndAreKnownSettings() throws {
        #expect(NodeSetting.all.isSuperset(of: [NodeSetting.pathRule, NodeSetting.branchPath, NodeSetting.itemPath]))
        var node = makeNode(ConstantNode.self)
        node.inputValues[NodeSetting.pathRule] = .text("{A;B} → {B;A}")
        node.inputValues[NodeSetting.branchPath] = .text("{0;3}")
        node.inputValues[NodeSetting.itemPath] = .text("{1;2}")
        let file = GraphFile(graph: graph([node]))
        let decoded = try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
        #expect(decoded.graph.nodes[node.id]?.inputValues[NodeSetting.pathRule] == .text("{A;B} → {B;A}"))
        #expect(decoded.graph.nodes[node.id]?.inputValues[NodeSetting.branchPath] == .text("{0;3}"))
        #expect(decoded.graph.nodes[node.id]?.inputValues[NodeSetting.itemPath] == .text("{1;2}"))
    }

    @Test func aNewerFileIsStillRefusedWithItsVersion() {
        #expect(throws: GraphFileError.newerFormat(7)) {
            try decode(#"{"formatVersion": 7, "graph": {"nodes": []}}"#)
        }
    }

    @Test func aTreeSocketAccessSurvivesAGroupInterfaceRoundTrip() throws {
        let interface = [SocketSpec("tree", .any, access: .tree), SocketSpec("count", .integer, defaultValue: .integer(2))]
        let decoded = try JSONDecoder().decode([SocketSpec].self, from: JSONEncoder().encode(interface))
        #expect(decoded == interface)
    }
}
