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
        #expect(NodeSetting.reservedForSockets.contains(NodeSetting.poleMoves))
        #expect(NodeSetting.all.contains(NodeSetting.poleMoves))
        #expect(NodeSetting.poleMoves == "poleMoves")
    }
}
