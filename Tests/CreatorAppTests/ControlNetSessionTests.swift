import CreatorGeometry
import Foundation
import CreatorGraph
import CreatorKernel
import CreatorViewport
import Testing
@testable import CreatorApp

/// The control-net tool's picking, box selection, dragging and overlay, with an orthographic projector at 1 mm per point.
@MainActor
struct ControlNetSessionTests {
    final class Log {
        var moves: [([PoleMove], ControlNetSession.DragPhase)] = []
        var ended = 0
    }

    /// An orthographic camera 200 points square showing 200 mm, so a point is a millimetre. Looks down -Z by default.
    static func projector(yaw: Double = 0, pitch: Double = .pi / 2) -> ViewportProjector {
        let distance = 100 / tan(CameraPose.fieldOfView / 2)
        return ViewportProjector(pose: CameraPose(target: .zero, distance: distance, yaw: yaw, pitch: pitch, projection: .orthographic),
                                 size: ViewportSize(width: 200, height: 200))
    }

    static func grid(_ u: Int, _ v: Int, normal: Vector3 = .unitZ, spacing: Double = 20) -> ControlNetGrid {
        var poles: [Vector3] = []
        for i in 0..<u { for j in 0..<v { poles.append(Vector3(Double(i) * spacing, Double(j) * spacing, 0)) } }
        return ControlNetGrid(poles: poles, uCount: u, vCount: v, normals: Array(repeating: normal, count: u * v))
    }

    func make(_ net: ControlNetGrid, kind: ControlNetSession.Kind = .surface) -> (ControlNetSession, Log) {
        let log = Log()
        let session = ControlNetSession(node: NodeID(), kind: kind, events: .init(
            moved: { log.moves.append(($0, $1)) }, ended: { log.ended += 1 }
        ))
        session.showNet(net, moves: [])
        return (session, log)
    }

    func screen(_ world: Vector3, _ projector: ViewportProjector) -> ScreenPoint {
        projector.screenPoint(of: world) ?? .zero
    }

    @Test func aClickPicksThePointWithin8Points() {
        let (session, _) = make(Self.grid(2, 2))
        let p = Self.projector()
        let target = screen(Vector3(20, 0, 0), p)
        #expect(session.clicked(at: ScreenPoint(target.x + 5, target.y + 5), modifiers: [], projector: p))
        #expect(session.selection == [PoleIndex(i: 1, j: 0)])
        _ = session.clicked(at: ScreenPoint(target.x + 9, target.y), modifiers: [], projector: p)
        #expect(session.selection.isEmpty)
    }

    @Test func shiftClickAdds() {
        let (session, _) = make(Self.grid(2, 2))
        let p = Self.projector()
        _ = session.clicked(at: screen(.zero, p), modifiers: [], projector: p)
        _ = session.clicked(at: screen(Vector3(20, 0, 0), p), modifiers: .shift, projector: p)
        #expect(session.selection == [PoleIndex(i: 0, j: 0), PoleIndex(i: 1, j: 0)])
    }

    @Test func commandClickToggles() {
        let (session, _) = make(Self.grid(2, 2))
        let p = Self.projector()
        _ = session.clicked(at: screen(.zero, p), modifiers: [], projector: p)
        _ = session.clicked(at: screen(Vector3(20, 0, 0), p), modifiers: .command, projector: p)
        _ = session.clicked(at: screen(.zero, p), modifiers: .command, projector: p)
        #expect(session.selection == [PoleIndex(i: 1, j: 0)])
    }

    @Test func aClickOnEmptySpaceClears() {
        let (session, _) = make(Self.grid(2, 2))
        let p = Self.projector()
        _ = session.clicked(at: screen(.zero, p), modifiers: [], projector: p)
        _ = session.clicked(at: ScreenPoint(190, 190), modifiers: [], projector: p)
        #expect(session.selection.isEmpty)
    }

    @Test func aDragOnEmptySpaceBoxSelects() {
        let (session, _) = make(Self.grid(2, 2))
        let p = Self.projector()
        let a = screen(Vector3(-10, -10, 0), p)
        // y is up on screen, so the box from (-10, -10) to (30, 10) in mm holds the two points with y == 0.
        let b = screen(Vector3(30, 10, 0), p)
        #expect(session.dragBegan(at: a, modifiers: [], projector: p))
        session.dragMoved(to: b, modifiers: [], projector: p)
        #expect(session.boxRect != nil)
        session.dragEnded(at: b, modifiers: [], projector: p)
        #expect(session.boxRect == nil)
        #expect(session.selection == [PoleIndex(i: 0, j: 0), PoleIndex(i: 1, j: 0)])
    }

    @Test func commandBoxToggles() {
        let (session, _) = make(Self.grid(2, 2))
        let p = Self.projector()
        _ = session.clicked(at: screen(.zero, p), modifiers: [], projector: p)
        let a = screen(Vector3(-10, -10, 0), p)
        let b = screen(Vector3(30, 10, 0), p)
        #expect(session.dragBegan(at: a, modifiers: .command, projector: p))
        session.dragMoved(to: b, modifiers: .command, projector: p)
        session.dragEnded(at: b, modifiers: .command, projector: p)
        #expect(session.selection == [PoleIndex(i: 1, j: 0)])
    }

    @Test func dragMovesTheSelectionInTheViewPlane() throws {
        let (session, log) = make(Self.grid(2, 2))
        let p = Self.projector()
        let start = screen(.zero, p)
        _ = session.clicked(at: start, modifiers: [], projector: p)
        _ = session.clicked(at: screen(Vector3(20, 0, 0), p), modifiers: .shift, projector: p)
        #expect(session.dragBegan(at: start, modifiers: [], projector: p))
        session.dragMoved(to: ScreenPoint(start.x + 5, start.y), modifiers: [], projector: p)
        let last = try #require(log.moves.last)
        #expect(last.1 == .changed)
        #expect(last.0.count == 2)
        for move in last.0 {
            #expect(abs(move.offset.x - 5) < 1e-6 && abs(move.offset.y) < 1e-6 && abs(move.offset.z) < 1e-6)
        }
    }

    @Test func zLockMovesAlongZOnly() throws {
        let (session, log) = make(Self.grid(2, 2))
        let p = Self.projector(yaw: .pi, pitch: 0)
        session.toggleLock(.z)
        let start = screen(.zero, p)
        _ = session.clicked(at: start, modifiers: [], projector: p)
        #expect(session.dragBegan(at: start, modifiers: [], projector: p))
        session.dragMoved(to: ScreenPoint(start.x + 7, start.y - 5), modifiers: [], projector: p)
        let move = try #require(log.moves.last?.0.first)
        #expect(abs(move.offset.z - 5) < 1e-6 && abs(move.offset.x) < 1e-6 && abs(move.offset.y) < 1e-6)
    }

    @Test func normalLockFollowsTheNormal() throws {
        let (session, log) = make(Self.grid(2, 2, normal: Vector3(1, 0, 0)))
        let p = Self.projector()
        session.toggleLock(.normal)
        let start = screen(.zero, p)
        _ = session.clicked(at: start, modifiers: [], projector: p)
        #expect(session.dragBegan(at: start, modifiers: [], projector: p))
        session.dragMoved(to: ScreenPoint(start.x + 4, start.y - 3), modifiers: [], projector: p)
        let move = try #require(log.moves.last?.0.first)
        #expect(abs(move.offset.x - 4) < 1e-6 && abs(move.offset.y) < 1e-6 && abs(move.offset.z) < 1e-6)
    }

    @Test func locksToggleAndNormalIsIgnoredOnACurve() {
        let (session, _) = make(Self.grid(2, 2))
        session.toggleLock(.x)
        #expect(session.lock == .x)
        session.toggleLock(.x)
        #expect(session.lock == nil)
        let curve = ControlNetGrid(poles: [.zero, Vector3(10, 0, 0)], uCount: 2, vCount: 1, normals: [])
        let (curveSession, _) = make(curve, kind: .curve)
        curveSession.toggleLock(.normal)
        #expect(curveSession.lock == nil)
    }

    @Test func aNetOfAnotherSizeClearsTheSelection() {
        let (session, _) = make(Self.grid(2, 2))
        let p = Self.projector()
        _ = session.clicked(at: screen(.zero, p), modifiers: [], projector: p)
        session.showNet(Self.grid(2, 2), moves: [])
        #expect(session.selection.count == 1)
        session.showNet(Self.grid(3, 2), moves: [])
        #expect(session.selection.isEmpty)
    }

    @Test func typingSetsTheOffset() throws {
        let (session, log) = make(Self.grid(2, 2))
        let p = Self.projector()
        _ = session.clicked(at: screen(.zero, p), modifiers: [], projector: p)
        session.setOffset(2, to: 3.5)
        let last = try #require(log.moves.last)
        #expect(last.1 == .typed)
        #expect(last.0 == [PoleMove(index: PoleIndex(i: 0, j: 0), offset: Vector3(0, 0, 3.5))])
    }

    @Test func theOverlayHasNetLinesAndPoints() {
        let (session, _) = make(Self.grid(3, 4))
        #expect(session.overlay.lines.count == 17)
        #expect(session.overlay.points.count == 12)
        #expect(session.overlay.lines.allSatisfy { $0.tint == .construction && $0.isDashed })
    }

    @Test func aDragEmitsOneEnded() {
        let (session, log) = make(Self.grid(2, 2))
        let p = Self.projector()
        let start = screen(.zero, p)
        _ = session.clicked(at: start, modifiers: [], projector: p)
        #expect(session.dragBegan(at: start, modifiers: [], projector: p))
        for step in 1...3 {
            session.dragMoved(to: ScreenPoint(start.x + Double(step), start.y), modifiers: [], projector: p)
        }
        session.dragEnded(at: ScreenPoint(start.x + 3, start.y), modifiers: [], projector: p)
        #expect(log.moves.filter { $0.1 == .ended }.count == 1)
        #expect(log.moves.filter { $0.1 == .changed }.count == 3)
    }
}
