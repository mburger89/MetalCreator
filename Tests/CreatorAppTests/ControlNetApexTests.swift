import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorViewport
import Testing
@testable import CreatorApp

/// NS-3 final review I1: poles that sit on one point (an apex) are picked and dragged as one.
@MainActor
struct ControlNetApexTests {
    let helper = ControlNetSessionTests()

    /// Three poles along u at v = 0 and the same three collapsed to one point at v = 1.
    static func apexNet() -> ControlNetGrid {
        var poles: [Vector3] = []
        for i in 0..<3 {
            poles.append(Vector3(Double(i) * 20, 0, 0))
            poles.append(Vector3(20, 30, 0))
        }
        return ControlNetGrid(poles: poles, uCount: 3, vCount: 2, normals: Array(repeating: .unitZ, count: 6))
    }

    static let apexRow: Set<PoleIndex> = [PoleIndex(i: 0, j: 1), PoleIndex(i: 1, j: 1), PoleIndex(i: 2, j: 1)]

    @Test func aClickOnAnApexSelectsTheWholeRow() {
        let (session, _) = helper.make(Self.apexNet())
        let p = ControlNetSessionTests.projector()
        _ = session.clicked(at: helper.screen(Vector3(20, 30, 0), p), modifiers: [], projector: p)
        #expect(session.selection == Self.apexRow)
        // ⌘ toggles the group off, ⇧ adds it.
        _ = session.clicked(at: helper.screen(Vector3(20, 30, 0), p), modifiers: .command, projector: p)
        #expect(session.selection.isEmpty)
        _ = session.clicked(at: helper.screen(.zero, p), modifiers: [], projector: p)
        _ = session.clicked(at: helper.screen(Vector3(20, 30, 0), p), modifiers: .shift, projector: p)
        #expect(session.selection == Self.apexRow.union([PoleIndex(i: 0, j: 0)]))
    }

    @Test func aBoxThatCatchesOneApexPoleCatchesAll() {
        let (session, _) = helper.make(Self.apexNet())
        let p = ControlNetSessionTests.projector()
        let a = helper.screen(Vector3(15, 25, 0), p)
        let b = helper.screen(Vector3(25, 35, 0), p)
        #expect(session.dragBegan(at: a, modifiers: [], projector: p))
        session.dragEnded(at: b, modifiers: [], projector: p)
        #expect(session.selection == Self.apexRow)
    }

    @Test func draggingAnApexMovesTheWholeRowTogether() throws {
        let (session, log) = helper.make(Self.apexNet())
        let p = ControlNetSessionTests.projector()
        let start = helper.screen(Vector3(20, 30, 0), p)
        #expect(session.dragBegan(at: start, modifiers: [], projector: p))
        session.dragMoved(to: ScreenPoint(start.x + 10, start.y), modifiers: [], projector: p)
        session.dragEnded(at: ScreenPoint(start.x + 10, start.y), modifiers: [], projector: p)
        let moved = try #require(log.moves.last?.0)
        #expect(Set(moved.map(\.index)) == Self.apexRow)
        #expect(Set(moved.map(\.offset)).count == 1)
    }
}
