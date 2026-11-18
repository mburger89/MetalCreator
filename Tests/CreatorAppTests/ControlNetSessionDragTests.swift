import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorViewport
import Testing
@testable import CreatorApp

/// The control-net tool's drags in perspective, cancelling, deferred nets and the overlay's priorities.
@MainActor
struct ControlNetSessionDragTests {
    typealias Base = ControlNetSessionTests

    private static func perspective() -> ViewportProjector {
        ViewportProjector(pose: CameraPose(target: Vector3(20, 20, 0), distance: 300, yaw: 0.3, pitch: 0.6),
                          size: ViewportSize(width: 400, height: 300))
    }

    @Test func aPressAndReleaseWithoutMovingEmitsNothing() {
        let (session, log) = Base().make(Base.grid(2, 2))
        let p = Base.projector()
        let start = Base().screen(.zero, p)
        #expect(session.dragBegan(at: start, modifiers: [], projector: p))
        session.dragEnded(at: start, modifiers: [], projector: p)
        #expect(log.moves.isEmpty)
        #expect(session.selection == [PoleIndex(i: 0, j: 0)])
    }

    @Test func aNetShownMidDragWaitsForTheEnd() {
        let (session, log) = Base().make(Base.grid(2, 2))
        let p = Base.projector()
        let start = Base().screen(.zero, p)
        _ = session.dragBegan(at: start, modifiers: [], projector: p)
        session.dragMoved(to: ScreenPoint(start.x + 2, start.y), modifiers: [], projector: p)
        session.showNet(Base.grid(2, 2, spacing: 40), moves: [])
        #expect(session.net.pole(PoleIndex(i: 1, j: 0)) == Vector3(20, 0, 0))
        session.dragEnded(at: ScreenPoint(start.x + 2, start.y), modifiers: [], projector: p)
        #expect(session.net.pole(PoleIndex(i: 1, j: 0)) == Vector3(40, 0, 0))
        #expect(abs((session.offsets[PoleIndex(i: 0, j: 0)]?.x ?? 0) - 2) < 1e-6)
        #expect(log.moves.filter { $0.1 == .ended }.count == 1)
    }

    @Test func escapeDuringADragCancelsItAndKeepsTheMode() throws {
        let (session, log) = Base().make(Base.grid(2, 2))
        let p = Base.projector()
        let start = Base().screen(.zero, p)
        _ = session.dragBegan(at: start, modifiers: [], projector: p)
        session.dragMoved(to: ScreenPoint(start.x + 6, start.y), modifiers: [], projector: p)
        session.cancel()
        let last = try #require(log.moves.last)
        #expect(last.1 == .cancelled)
        #expect(last.0 == [PoleMove(index: PoleIndex(i: 0, j: 0), offset: .zero)])
        #expect(log.ended == 0)
        #expect(session.offsets[PoleIndex(i: 0, j: 0)] == .zero)
        session.dragEnded(at: ScreenPoint(start.x + 6, start.y), modifiers: [], projector: p)
        #expect(log.moves.filter { $0.1 == .ended }.isEmpty)
    }

    @Test func escapeWithNoDragLeavesTheMode() {
        let (session, log) = Base().make(Base.grid(2, 2))
        session.cancel()
        #expect(log.ended == 1)
    }

    @Test func aPerspectiveDragKeepsThePointUnderThePointer() throws {
        let (session, _) = Base().make(Base.grid(2, 2))
        let p = Self.perspective()
        let start = Base().screen(Vector3(20, 0, 0), p)
        _ = session.dragBegan(at: start, modifiers: [], projector: p)
        let target = ScreenPoint(start.x + 37, start.y - 21)
        session.dragMoved(to: target, modifiers: [], projector: p)
        let world = try #require(session.position(of: PoleIndex(i: 1, j: 0)))
        let landed = Base().screen(world, p)
        #expect(abs(landed.x - target.x) < 1e-6 && abs(landed.y - target.y) < 1e-6)
    }

    @Test func anXLockInPerspectiveLandsAtTheClosestPoint() throws {
        let (session, _) = Base().make(Base.grid(2, 2))
        let p = Self.perspective()
        session.toggleLock(.x)
        let start = Base().screen(Vector3(20, 0, 0), p)
        _ = session.dragBegan(at: start, modifiers: [], projector: p)
        let target = ScreenPoint(start.x + 30, start.y + 12)
        session.dragMoved(to: target, modifiers: [], projector: p)
        let world = try #require(session.position(of: PoleIndex(i: 1, j: 0)))
        #expect(abs(world.y) < 1e-9 && abs(world.z) < 1e-9)
        let ray = try #require(p.ray(through: target))
        let onRay = ray.origin + ray.direction * (world - ray.origin).dot(ray.direction)
        #expect(abs((onRay - world).dot(.unitX)) < 1e-6)
        #expect(world.x != 20)
    }

    @Test func anAxisPointingAtTheCameraMovesWithVerticalPointerMotion() throws {
        let (session, _) = Base().make(Base.grid(2, 2))
        let p = Base.projector()
        session.toggleLock(.z)
        let start = Base().screen(.zero, p)
        _ = session.dragBegan(at: start, modifiers: [], projector: p)
        session.dragMoved(to: ScreenPoint(start.x + 9, start.y - 10), modifiers: [], projector: p)
        let offset = try #require(session.offsets[PoleIndex(i: 0, j: 0)])
        #expect(abs(offset.z - 10) < 1e-6 && abs(offset.x) < 1e-9 && abs(offset.y) < 1e-9)
    }

    @Test func aNormalLockWithNoNormalMovesNothing() throws {
        let net = ControlNetGrid(poles: Base.grid(2, 2).poles, uCount: 2, vCount: 2, normals: [])
        let (session, log) = Base().make(net)
        let p = Base.projector()
        session.toggleLock(.normal)
        let start = Base().screen(.zero, p)
        _ = session.dragBegan(at: start, modifiers: [], projector: p)
        session.dragMoved(to: ScreenPoint(start.x + 5, start.y), modifiers: [], projector: p)
        let move = try #require(log.moves.last?.0.first)
        #expect(move.offset == .zero)
    }

    @Test func aDragOnAnUnselectedPointSelectsItFirst() {
        let (session, _) = Base().make(Base.grid(2, 2))
        let p = Base.projector()
        _ = session.clicked(at: Base().screen(.zero, p), modifiers: [], projector: p)
        #expect(session.dragBegan(at: Base().screen(Vector3(20, 20, 0), p), modifiers: [], projector: p))
        #expect(session.selection == [PoleIndex(i: 1, j: 1)])
    }

    @Test func theNearestToTheCameraWinsATie() {
        let net = ControlNetGrid(poles: [.zero, Vector3(0, 0, 5)], uCount: 2, vCount: 1, normals: [])
        let (session, _) = Base().make(net, kind: .curve)
        let p = Base.projector()
        _ = session.clicked(at: Base().screen(.zero, p), modifiers: [], projector: p)
        #expect(session.selection == [PoleIndex(i: 1, j: 0)])
    }

    @Test func selectedBeatsHoveredInTheOverlay() {
        let (session, _) = Base().make(Base.grid(2, 2))
        let p = Base.projector()
        _ = session.clicked(at: Base().screen(.zero, p), modifiers: [], projector: p)
        session.pointerMoved(to: Base().screen(.zero, p), modifiers: [], projector: p)
        #expect(session.hover == PoleIndex(i: 0, j: 0))
        #expect(session.overlay.points.filter { $0.tint == .selected }.count == 1)
        #expect(session.overlay.points.filter { $0.tint == .hovered }.isEmpty)
    }
}
