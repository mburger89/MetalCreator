import CreatorGeometry
import Testing
@testable import CreatorPCB

struct KeyAssignerTests {
    private func footprint(_ reference: String, uuid: String? = nil, numbers: [String]) -> Footprint {
        Footprint(reference: reference, libraryID: "L:F", uuid: uuid, isBack: false, place: .identity,
                  holes: numbers.map { DrilledHole(center: .zero, diameter: 1, isPlated: true, padNumber: $0) }, models: [])
    }

    @Test func repeatedPadNumbersGetSuffixes() throws {
        var board = KiCadBoard(footprints: [footprint("J1", numbers: ["1", "1", "2", "1"])])
        try KeyAssigner.assign(&board)
        #expect(board.footprints[0].holes.map(\.identity) == ["pad:J1:1", "pad:J1:1:2", "pad:J1:2", "pad:J1:1:3"])
    }

    @Test func emptyReferenceUsesUUID() throws {
        var board = KiCadBoard(footprints: [footprint("", uuid: "abc", numbers: ["1"])])
        try KeyAssigner.assign(&board)
        #expect(board.footprints[0].holes[0].identity == "pad:uuid:abc:1")
    }

    @Test func repeatedReferencesUseUUIDs() throws {
        let footprints = [
            footprint("H1", uuid: "u1", numbers: ["1"]),
            footprint("H1", uuid: "u2", numbers: ["1"]),
            footprint("", numbers: ["1"]),
        ]
        var board = KiCadBoard(footprints: footprints)
        try KeyAssigner.assign(&board)
        #expect(board.footprints.map { $0.holes[0].identity } == ["pad:uuid:u1:1", "pad:uuid:u2:1", "pad:fp#2:1"])
    }

    @Test func viasAreNamedByPosition() throws {
        var board = KiCadBoard(vias: [DrilledHole(center: Vector2(1.5, -2.0000004), diameter: 0.3, isPlated: true)])
        try KeyAssigner.assign(&board)
        #expect(board.vias[0].identity == "via:1.500000,-2.000000")
    }

    @Test func viaUUIDNamesTheVia() throws {
        var board = KiCadBoard(vias: [DrilledHole(center: .zero, diameter: 0.3, isPlated: true, uuid: "v-1")])
        try KeyAssigner.assign(&board)
        #expect(board.vias[0].identity == "via:v-1")
    }

    @Test func everyIdentityIsUnique() throws {
        var board = KiCadBoard(edgeItems: [EdgeItem(shape: .line(.zero, Vector2(1, 0)), identity: "edge:u"),
                                           EdgeItem(shape: .line(.zero, Vector2(0, 1)), identity: "edge:u"),
                                           ],
                               footprints: [footprint("J1", numbers: ["1", "1", "1:2"])])
        try KeyAssigner.assign(&board)
        let all = board.edgeItems.map(\.identity) + board.footprints[0].holes.map(\.identity)
        #expect(Set(all).count == all.count)
        #expect(board.edgeItems.map(\.identity) == ["edge:u", "edge:u#2"])
        #expect(board.footprints[0].holes.map(\.identity) == ["pad:J1:1", "pad:J1:1:2", "pad:J1:1:2#2"])
    }

    @Test func aForcedCollisionRefuses() {
        var board = KiCadBoard(footprints: [footprint("A", numbers: ["1"]), footprint("B", numbers: ["1"])])
        do {
            try KeyAssigner.assign(&board, hash: { _ in 7 })
            Issue.record("expected a refusal")
        } catch let problem as KiCadProblem {
            #expect(problem.message == "Two items in this board share an internal name (fp:A and pad:A:1). "
                + "Rename one in KiCad and try again.")
        } catch {
            Issue.record("wrong error")
        }
    }

    @Test func footprintsGetIdentitiesFromTheirTokens() throws {
        let footprints = [footprint("H1", uuid: "u1", numbers: []), footprint("H1", uuid: "u2", numbers: []),
                          footprint("J1", numbers: ["1"]), footprint("", numbers: []),
        ]
        var board = KiCadBoard(footprints: footprints)
        try KeyAssigner.assign(&board)
        #expect(board.footprints.map(\.identity) == ["fp:uuid:u1", "fp:uuid:u2", "fp:J1", "fp:fp#3"])
    }
}
