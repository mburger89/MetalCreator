import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// File format 8 (implicit spec §5.4): `implicit` and `mesh` sockets on a group's interface, and files of formats 1 to 7 opening
/// unchanged.
struct ImplicitFileTests {
    func reopened(_ file: GraphFile) throws -> GraphFile {
        try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
    }

    @Test func theFormatIsNine() {
        #expect(GraphFile.currentFormatVersion == 9, "9: cable ties, after 8's implicit sockets")
    }

    @Test func aGroupInterfaceMayCarryImplicitAndMeshSockets() throws {
        var group = GroupFixture()
        group.definition.inputs = [SocketSpec("shape", .implicit), SocketSpec("count", .integer, defaultValue: .integer(2))]
        group.definition.outputs = [SocketSpec("solid", .implicit), SocketSpec("surface", .mesh, access: .list, optional: true)]
        let file = GraphFile(graph: Graph(), definitions: [group.definition.id: group.definition])
        let back = try reopened(file)
        #expect(back.formatVersion == 9)
        #expect(back.definitions[group.definition.id]?.inputs == group.definition.inputs)
        #expect(back.definitions[group.definition.id]?.outputs == group.definition.outputs)
        let text = try #require(String(bytes: try GraphFileIO.encode(file), encoding: .utf8))
        #expect(text.contains("\"implicit\"") && text.contains("\"mesh\""))
    }

    @Test func theSocketTypesKeepTheirNamesInFiles() throws {
        let encoded = try JSONEncoder().encode([SocketType.implicit, SocketType.mesh])
        #expect(String(bytes: encoded, encoding: .utf8) == #"["implicit","mesh"]"#)
        #expect(try JSONDecoder().decode([SocketType].self, from: encoded) == [.implicit, .mesh])
    }

    @Test(arguments: 1...7)
    func aFileOfAnyEarlierFormatOpensUnchangedAndSavesAsEight(_ version: Int) throws {
        let id = NodeID()
        let json = """
        {"formatVersion": \(version), "graph": {"nodes": [{"id": "\(id.rawValue.uuidString)", "typeID": "test.constant",
        "typeVersion": 1, "name": "Constant", "position": {"x": 0, "y": 0}, "isOutput": false,
        "inputValues": {"value": {"type": "number", "value": 4}}}], "links": []}}
        """
        let file = try GraphFileIO.decode(Data(json.utf8), registry: testRegistry)
        #expect(file.formatVersion == version && file.graph.nodes[id]?.inputValues["value"] == .number(4))
        let saved = try reopened(GraphFile(graph: file.graph, definitions: file.definitions, viewState: file.viewState))
        #expect(saved.formatVersion == 9 && saved.graph == file.graph)
    }
}

/// A one-socket group definition, to put sockets on.
private struct GroupFixture {
    var definition = GroupDefinition(id: GroupID(), name: "Shape", inputs: [], outputs: [], graph: Graph())
}
