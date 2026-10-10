import CreatorKernel
import Foundation
import Testing
@testable import CreatorGraph

struct GroupFileTests {
    @Test func definitionsRoundTripWithTheirInstances() throws {
        let doubler = Doubler()
        let node = instance(of: doubler.definition, ["value": .number(3)], output: true)
        let file = GraphFile(graph: graph([node]), definitions: table([doubler.definition]))
        let decoded = try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
        #expect(decoded == file)
    }

    @Test func definitionsAreWrittenSortedByID() throws {
        let definitions = (0..<4).map { GroupDefinition(name: "Group \($0)") }
        let data = try GraphFileIO.encode(GraphFile(definitions: table(definitions)))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let written = try #require(json["definitions"] as? [[String: Any]]).compactMap { $0["id"] as? String }
        #expect(written == definitions.map(\.id).sorted().map(\.rawValue.uuidString))
    }

    @Test func aVersionFourFileOpensWithNoDefinitions() throws {
        let id = NodeID()
        let json = """
        {"formatVersion": 4, "graph": {"nodes": [{"id": "\(id.rawValue.uuidString)", "typeID": "test.constant",
        "typeVersion": 1, "name": "Constant", "position": {"x": 0, "y": 0}, "isOutput": false,
        "inputValues": {"value": {"type": "number", "value": 2}}}]}}
        """
        let file = try GraphFileIO.decode(Data(json.utf8), registry: testRegistry)
        #expect(file.definitions.isEmpty)
        #expect(file.graph.nodes[id]?.inputValues["value"] == .number(2))
    }

    /// 5 since groups (C1). Comments (B) add their keys under the same version; whichever merges first bumps.
    @Test func savedFilesAreFormatFive() throws {
        #expect(GraphFile.currentFormatVersion == 5)
        let text = try #require(String(bytes: try GraphFileIO.encode(GraphFile()), encoding: .utf8))
        #expect(text.contains(#""formatVersion" : 5"#))
        #expect(text.contains(#""definitions" : ["#))
    }

    @Test func nodesInsideDefinitionsAreMigratedOnLoad() throws {
        var definition = GroupDefinition.make(name: "Old", registry: testRegistry)
        var old = makeNode(VersionedNode.self, ["old": .number(3)])
        old.typeVersion = 1
        definition.graph.nodes[old.id] = old
        let file = GraphFile(definitions: table([definition]))
        let decoded = try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
        let migrated = try #require(decoded.definitions[definition.id]?.graph.nodes[old.id])
        #expect(migrated.typeVersion == 2)
        #expect(migrated.inputValues == ["value": .number(3)])
    }
}
