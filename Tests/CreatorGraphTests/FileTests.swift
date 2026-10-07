import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorGraph

struct FileTests {
    @Test func graphRoundTrips() throws {
        let a = makeNode(ConstantNode.self, ["value": .number(6)]), b = makeNode(AddNode.self, output: true)
        let parameter = GraphParameter(name: "Wall", type: .number, value: .number(6), min: 1, max: 20)
        let file = GraphFile(graph: graph([a, b], [link(a, "value", b, "a")], parameters: [parameter]),
                             viewState: ViewState(dock: .bottom, canvasOffset: Vector2(10, 20), canvasZoom: 1.5))
        let decoded = try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
        #expect(decoded == file)
    }

    @Test func encodingIsDeterministic() throws {
        let file = GraphFile(graph: graph([makeNode(ConstantNode.self), makeNode(AddNode.self)]))
        #expect(try GraphFileIO.encode(file) == GraphFileIO.encode(file))
    }

    @Test func unknownNodeRoundTrips() throws {
        var future = makeNode(ConstantNode.self, ["mystery": .text("keep me")])
        future.typeID = "future.node"
        future.typeVersion = 7
        let file = GraphFile(graph: graph([future]))
        let decoded = try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
        #expect(decoded.graph.nodes[future.id] == future)
    }

    @Test func oldNodeVersionsAreMigratedOnLoad() throws {
        var old = makeNode(VersionedNode.self, ["old": .number(3)])
        old.typeVersion = 1
        let decoded = try GraphFileIO.decode(try GraphFileIO.encode(GraphFile(graph: graph([old]))), registry: testRegistry)
        let migrated = try #require(decoded.graph.nodes[old.id])
        #expect(migrated.typeVersion == 2)
        #expect(migrated.inputValues == ["value": .number(3)])
    }

    @Test func newerFormatIsRefusedWithItsVersion() throws {
        let json = #"{"formatVersion": 99, "graph": {"nodes": [], "links": [], "parameters": []}}"#
        #expect(throws: GraphFileError.newerFormat(99)) {
            try GraphFileIO.decode(Data(json.utf8), registry: testRegistry)
        }
    }

    @Test func missingViewStateUsesDefaults() throws {
        let json = #"{"formatVersion": 1, "graph": {"nodes": []}}"#
        let file = try GraphFileIO.decode(Data(json.utf8), registry: testRegistry)
        #expect(file.viewState == ViewState())
        #expect(file.viewState.dock == .left)
    }

    @Test func newerFormatWithChangedShapeIsStillRecognised() throws {
        let json = #"{"formatVersion": 99, "graph": "future shape"}"#
        #expect(throws: GraphFileError.newerFormat(99)) {
            try GraphFileIO.decode(Data(json.utf8), registry: testRegistry)
        }
    }

    @Test func newerNodeVersionIsNotMigrated() throws {
        var newer = makeNode(VersionedNode.self, ["old": .number(3)])
        newer.typeVersion = 3
        let file = GraphFile(graph: graph([newer]))
        let decoded = try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
        let preserved = try #require(decoded.graph.nodes[newer.id])
        #expect(preserved.typeVersion == 3)
        #expect(preserved.inputValues == ["old": .number(3)])
    }

    @Test func malformedJSONThrowsInsteadOfCrashing() {
        #expect(throws: DecodingError.self) { try GraphFileIO.decode(Data("{ not json".utf8), registry: testRegistry) }
    }
}
