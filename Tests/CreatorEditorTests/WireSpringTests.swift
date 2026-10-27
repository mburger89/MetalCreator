import CreatorGeometry
import Testing
@testable import CreatorEditor

/// One piece's spring (cable ties spec 2026-10-26 §5.2). A moved end pulls its control point behind it by 60% of the move;
/// the offset never passes 40% of the piece's length; it settles, to the eye, within about 0.3 s, and then to exactly
/// zero; the solution is exact, so one long frame equals many short ones.
struct WireSpringTests {
    let frame = 1.0 / 60

    func run(_ state: PieceSpring, frames: Int) -> PieceSpring {
        (0..<frames).reduce(state) { spring, _ in
            WireSpring.step(spring, startDelta: .zero, endDelta: .zero, length: 100, dt: frame)
        }
    }

    @Test func aMovedEndPullsItsControlPointBehindIt() {
        let kicked = WireSpring.kick(PieceSpring(), startDelta: .zero, endDelta: Vector2(20, 0), length: 100)
        #expect(abs(kicked.control2.offset.x + 12) < 1e-12 && kicked.control2.offset.y == 0, "60% of the move, against it")
        #expect(kicked.control1 == SpringPoint(), "the end that did not move keeps its control point")
        #expect(!kicked.isAtRest)
    }

    @Test func theOffsetIsCappedAtFortyPercentOfThePiece() {
        let kicked = WireSpring.kick(PieceSpring(), startDelta: Vector2(0, 500), endDelta: .zero, length: 100)
        #expect(abs(kicked.control1.offset.length - 40) < 1e-9)
        #expect(kicked.control1.offset.x == 0 && kicked.control1.offset.y < 0)
        for frames in [1, 2, 5, 10, 20] {
            #expect(run(kicked, frames: frames).control1.offset.length <= 40 + 1e-9, "\(frames) frames")
        }
    }

    @Test func itSettlesWithinTheBudgetToExactlyZero() {
        let kicked = WireSpring.kick(PieceSpring(), startDelta: .zero, endDelta: Vector2(100, 0), length: 100)
        #expect(abs(kicked.control2.offset.x + 40) < 1e-9, "set up: at the cap")
        #expect(run(kicked, frames: 18).control2.offset.length < 1, "under 2.5% of the slack after 0.3 s")
        #expect(run(kicked, frames: 30) == PieceSpring(), "exactly zero after 0.5 s")
    }

    @Test func oneLongFrameIsTheSameAsManyShortOnes() {
        let kicked = WireSpring.kick(PieceSpring(), startDelta: .zero, endDelta: Vector2(100, 0), length: 100)
        let short = run(kicked, frames: 10)
        let once = WireSpring.evolve(kicked, dt: 10 * frame)
        #expect(abs(short.control2.offset.x - once.control2.offset.x) < 1e-9, "the solution is exact, not stepped")
        #expect(abs(short.control2.velocity.x - once.control2.velocity.x) < 1e-6)
        #expect(WireSpring.evolve(kicked, dt: 0.5) == PieceSpring(), "half a second at once settles too")
        #expect(WireSpring.evolve(kicked, dt: 30).isAtRest, "and a very long frame never overshoots")
    }

    @Test func nothingMovedAndNoTimeChangesNothing() {
        let kicked = WireSpring.kick(PieceSpring(), startDelta: Vector2(10, 10), endDelta: .zero, length: 100)
        #expect(WireSpring.step(kicked, startDelta: .zero, endDelta: .zero, length: 100, dt: 0).control1 == kicked.control1)
        #expect(WireSpring.evolve(kicked, dt: -1) == kicked)
        #expect(WireSpring.kick(PieceSpring(), startDelta: Vector2(0.01, 0), endDelta: .zero, length: 100) == PieceSpring(),
                "a move too small to see is no slack")
    }
}
