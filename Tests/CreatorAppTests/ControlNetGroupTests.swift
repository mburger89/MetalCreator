import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorViewport
import Testing
@testable import CreatorApp

/// NS-4 Task 2: coincident poles group by one tolerance, and typing or dragging a group moves all of it.
@MainActor
struct ControlNetGroupTests {
    let helper = ControlNetSessionTests()

    static func line(_ xs: [Double]) -> ControlNetGrid {
        ControlNetGrid(poles: xs.enumerated().map { Vector3($0.element, Double($0.offset) * 10, 0) }.map { Vector3($0.x, 0, 0) },
                       uCount: xs.count, vCount: 1, normals: Array(repeating: .unitZ, count: xs.count))
    }

    @Test func groupingIsTransitiveWithinTheTolerance() {
        let (session, _) = helper.make(Self.line([0, 0.6e-6, 1.2e-6]))
        let all: Set<PoleIndex> = [PoleIndex(i: 0, j: 0), PoleIndex(i: 1, j: 0), PoleIndex(i: 2, j: 0)]
        #expect(session.group(of: PoleIndex(i: 0, j: 0)) == all)
        #expect(session.group(of: PoleIndex(i: 2, j: 0)) == all)
    }

    @Test func polesFurtherApartAreSeparate() {
        let (session, _) = helper.make(Self.line([0, 2e-6]))
        #expect(session.group(of: PoleIndex(i: 0, j: 0)) == [PoleIndex(i: 0, j: 0)])
    }

    @Test func aConstantXNetGroupsQuickly() {
        var poles: [Vector3] = []
        for i in 0..<300 { for j in 0..<300 { poles.append(Vector3(0, Double(i) * 0.5, Double(j) * 0.5)) } }
        let net = ControlNetGrid(poles: poles, uCount: 300, vCount: 300, normals: Array(repeating: .unitX, count: poles.count))
        let clock = ContinuousClock()
        var session: ControlNetSession?
        let elapsed = clock.measure { session = helper.make(net).0 }
        #expect(elapsed < .seconds(5))
        #expect(session?.coincident.isEmpty == true)
    }

    @Test func typingOnAnApexMovesTheWholeGroup() throws {
        let (session, log) = helper.make(ControlNetApexTests.apexNet())
        session.selection = ControlNetApexTests.apexRow
        #expect(session.typedTarget == PoleIndex(i: 0, j: 1))
        session.setOffset(2, to: 2)
        #expect(log.moves.count == 1)
        let (moves, phase) = try #require(log.moves.last)
        #expect(phase == .typed)
        #expect(moves.count == 3)
        #expect(moves.allSatisfy { $0.offset == Vector3(0, 0, 2) })
    }

    @Test func typingAGroupIsOneStep() async throws {
        let modes = ControlNetModeTests()
        let fixture = await modes.open()
        let session = try await modes.enter(fixture)
        var poles = session.net.poles
        poles[1] = poles[0]
        poles[2] = poles[0]
        var net = session.net
        net.poles = poles
        session.showNet(net, moves: [])
        session.selection = session.group(of: PoleIndex(i: 0, j: 0))
        #expect(session.selection.count == 3)
        session.setOffset(0, to: 1)
        #expect(fixture.app.document.undoName == "Change Control Point")
        #expect(modes.moves(fixture).count == 3)
        fixture.app.document.undo()
        #expect(modes.moves(fixture).isEmpty)
    }

    @Test func aDragOnAPartlySelectedGroupMovesTheWholeGroup() throws {
        let (session, log) = helper.make(ControlNetApexTests.apexNet())
        let p = ControlNetSessionTests.projector()
        session.selection = [PoleIndex(i: 1, j: 1), PoleIndex(i: 2, j: 1)]
        let start = helper.screen(Vector3(20, 30, 0), p)
        #expect(session.dragBegan(at: start, modifiers: [], projector: p))
        session.dragMoved(to: ScreenPoint(start.x + 10, start.y), modifiers: [], projector: p)
        session.dragEnded(at: ScreenPoint(start.x + 10, start.y), modifiers: [], projector: p)
        let moved = try #require(log.moves.last?.0)
        #expect(Set(moved.map(\.index)) == ControlNetApexTests.apexRow)
    }

    @Test func theSelectionCountsAGroupOnce() {
        let (session, _) = helper.make(ControlNetApexTests.apexNet())
        session.selection = ControlNetApexTests.apexRow
        #expect(ControlNetInspector.selectionText(points: session.selection, in: session) == "1 point selected")
    }
}
