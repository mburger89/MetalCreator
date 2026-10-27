import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorGraph

/// Ties are saved with their graph (cable ties spec 2026-10-26 §3.3): format 9, the key written only when there are some,
/// sorted by id with each tie's wires sorted, and decoding repairs (I1) and then (I2).
@MainActor
struct TieFileTests {
    let scene = TieGraph()

    func json(_ file: GraphFile) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: try GraphFileIO.encode(file)) as? [String: Any])
    }

    func reopened(_ file: GraphFile) throws -> GraphFile {
        try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
    }

    @Test func tiesRoundTripOnTheTopLevelAndInsideADefinition() throws {
        let doubler = Doubler()
        var definition = doubler.definition
        let inside = [Endpoint(node: doubler.add.id, socket: "a"), Endpoint(node: doubler.add.id, socket: "b")]
        definition.graph.ties[tieID(5)] = tie(5, inside)
        let top = scene.make(ties: [
            tie(1, [scene.s1a, scene.s1b]),
            tie(2, [scene.s1b, scene.s2a, scene.s2b], at: Vector2(-30.5, 1e6)),
        ])
        let file = GraphFile(graph: top, definitions: table([definition]))
        #expect(try reopened(file) == file)
    }

    @Test func tiesAreWrittenSortedByIDWithTheirWiresSorted() throws {
        let ids = [7, 3, 9, 1]
        let file = GraphFile(graph: scene.make(ties: ids.map { tie($0, [scene.s2b, scene.s1a, scene.s2a]) }))
        let graph = try #require(try json(file)["graph"] as? [String: Any])
        let written = try #require(graph["ties"] as? [[String: Any]])
        #expect(written.compactMap { $0["id"] as? String } == ids.sorted().map { tieID($0).rawValue.uuidString })
        let wires = try #require(written.first?["wires"] as? [[String: Any]])
        let sorted = [scene.s1a, scene.s2a, scene.s2b].sorted()
        #expect(wires.compactMap { $0["node"] as? String } == sorted.map(\.node.rawValue.uuidString))
        #expect(wires.compactMap { $0["socket"] as? String } == sorted.map(\.socket.rawValue))
        #expect(try GraphFileIO.encode(file) == GraphFileIO.encode(file), "deterministic")
    }

    @Test func aGraphWithoutTiesIsWrittenWithoutTheKey() throws {
        let graph = try #require(try json(GraphFile(graph: scene.make()))["graph"] as? [String: Any])
        #expect(graph["ties"] == nil)
    }

    /// (I1) first, then (I2): a wire that is no link's input goes, and a tie that is then left with one wire goes too.
    @Test func decodingDropsWiresThatAreNotThereAndThenSmallTies() throws {
        let gone = Endpoint(node: NodeID(), socket: "a")
        var written = scene.make()
        written.ties[tieID(1)] = tie(1, [scene.s1a, gone])
        written.ties[tieID(2)] = tie(2, [scene.s1a, scene.s1b, gone])
        written.ties[tieID(3)] = tie(3, [scene.s2a, scene.s2b])
        let decoded = try reopened(GraphFile(graph: written)).graph
        #expect(decoded.ties == [tieID(2): tie(2, [scene.s1a, scene.s1b]), tieID(3): tie(3, [scene.s2a, scene.s2b])])
    }

    @Test func aRepeatedTieIDKeepsTheFirst() throws {
        let first = tie(1, [scene.s1a, scene.s1b])
        var object = try json(GraphFile(graph: scene.make(ties: [first])))
        var graph = try #require(object["graph"] as? [String: Any])
        var written = try #require(graph["ties"] as? [[String: Any]])
        var copy = try #require(written.first)
        copy["position"] = ["x": 999, "y": 999]
        written.append(copy)
        graph["ties"] = written
        object["graph"] = graph
        let decoded = try GraphFileIO.decode(try JSONSerialization.data(withJSONObject: object), registry: testRegistry)
        #expect(decoded.graph.ties == [first.id: first])
    }

    @Test func aFormatEightFileHasNoTies() throws {
        let id = NodeID()
        let text = """
        {"formatVersion": 8, "graph": {"nodes": [{"id": "\(id.rawValue.uuidString)", "typeID": "test.constant",
        "typeVersion": 1, "name": "Constant", "position": {"x": 0, "y": 0}, "isOutput": false,
        "inputValues": {"value": {"type": "number", "value": 2}}}]}}
        """
        let file = try GraphFileIO.decode(Data(text.utf8), registry: testRegistry)
        #expect(file.graph.ties.isEmpty)
        #expect(file.graph.nodes[id]?.inputValues["value"] == .number(2))
    }

    @Test func filesAreWrittenAsFormatNineAndTenIsRefused() throws {
        #expect(GraphFile.currentFormatVersion == 9, "9: cable ties")
        let text = try #require(String(bytes: try GraphFileIO.encode(GraphFile()), encoding: .utf8))
        #expect(text.contains(#""formatVersion" : 9"#))
        #expect(throws: GraphFileError.newerFormat(10)) {
            try GraphFileIO.decode(Data(#"{"formatVersion": 10, "graph": {"nodes": []}}"#.utf8), registry: testRegistry)
        }
    }
}
