import CreatorGeometry
import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

struct PoleMovesFileTests {
    @Test func poleMovesRoundTrip() throws {
        let moves = [
            PoleMove(index: PoleIndex(i: 2, j: 1), offset: Vector3(1, 2, 3)),
            PoleMove(index: PoleIndex(i: 0, j: 3), offset: Vector3(0, -1, 0.5)),
            PoleMove(index: PoleIndex(i: 2, j: 0), offset: Vector3(4, 0, 0)),
        ]
        let value = ConstantValue.poleMoves(moves)
        let data = try JSONEncoder().encode(value)
        let back = try JSONDecoder().decode(ConstantValue.self, from: data)
        #expect(back == .poleMoves(moves.sorted { $0.index < $1.index }))
        guard case .poleMoves(let stored) = back else { Issue.record("kind"); return }
        #expect(stored.map(\.index) == [PoleIndex(i: 0, j: 3), PoleIndex(i: 2, j: 0), PoleIndex(i: 2, j: 1)])
        let text = try #require(String(bytes: data, encoding: .utf8))
        #expect(text.contains("poleMoves") && text.contains("\"offset\""))
    }

    @Test func aFormat14FileOpens() throws {
        let json = #"{"formatVersion": 14, "graph": {"nodes": []}}"#
        let file = try GraphFileIO.decode(Data(json.utf8), registry: testRegistry)
        #expect(file.graph == Graph())
        #expect(GraphFile.currentFormatVersion == 15)
    }

    @Test func nonFiniteOffsetsAreRejected() {
        let bad = PoleMove(index: PoleIndex(i: 0), offset: Vector3(.nan, 0, 0))
        #expect(!ConstantValue.poleMoves([bad]).isFinite)
        #expect(ConstantValue.poleMoves([PoleMove(index: PoleIndex(i: 0), offset: Vector3(1, 0, 0))]).isFinite)
    }

    @Test func theSettingIsReserved() {
        // A setting name, but not reserved: a group socket or exposed dimension called "poleMoves" keeps working (M2).
        #expect(!NodeSetting.reservedForSockets.contains(NodeSetting.poleMoves))
        #expect(NodeSetting.all.contains(NodeSetting.poleMoves))
        #expect(NodeSetting.poleMoves == "poleMoves")
    }

    @Test func negativeIndicesAreDroppedOnDecode() throws {
        let moves = [move(-1, 0, 1), move(2, 1, 2), move(0, -3, 3)]
        let payload = String(bytes: try JSONEncoder().encode(moves), encoding: .utf8) ?? ""
        let json = #"{"type":"poleMoves","value":"# + payload + "}"
        let value = try JSONDecoder().decode(ConstantValue.self, from: Data(json.utf8))
        #expect(value == .poleMoves([move(2, 1, 2)]))
    }

    private func move(_ i: Int, _ j: Int = 0, _ x: Double = 0) -> PoleMove {
        PoleMove(index: PoleIndex(i: i, j: j), offset: Vector3(x, 0, 0))
    }

    private func applying(_ value: ConstantValue) throws -> ConstantValue? {
        let node = makeNode(ConstantNode.self)
        var graph = Graph(nodes: [node.id: node])
        try graph.apply(.setInput(node.id, NodeSetting.poleMoves, value), registry: testRegistry)
        return graph.nodes[node.id]?.inputValues[NodeSetting.poleMoves]
    }

    @Test func setInputCanonicalisesPoleMoves() throws {
        let stored = try applying(.poleMoves([move(2, 0, 1), move(0, 1, 2), move(2, 0, 9)]))
        #expect(stored == .poleMoves([move(0, 1, 2), move(2, 0, 1)]))
    }

    @Test func decodeKeepsTheFirstOfADuplicate() throws {
        let json = #"{"type":"poleMoves","value":[{"i":1,"j":0,"offset":{"x":1,"y":0,"z":0}},{"i":1,"j":0,"offset":{"x":5,"y":0,"z":0}}]}"#
        let value = try JSONDecoder().decode(ConstantValue.self, from: Data(json.utf8))
        #expect(value == .poleMoves([move(1, 0, 1)]))
    }

    @Test func setInputRefusesANonFiniteOffset() {
        let bad = PoleMove(index: PoleIndex(i: 0), offset: Vector3(0, .infinity, 0))
        #expect(throws: GraphError.invalidValue("Enter a finite number.")) { try applying(.poleMoves([bad])) }
    }

    @Test func setInputRefusesANegativeIndex() {
        #expect(throws: GraphError.invalidValue("A control point index can't be negative.")) { try applying(.poleMoves([move(-1)])) }
        #expect(throws: GraphError.invalidValue("A control point index can't be negative.")) { try applying(.poleMoves([move(0, -2)])) }
    }
}
