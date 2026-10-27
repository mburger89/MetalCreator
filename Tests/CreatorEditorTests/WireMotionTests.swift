import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Every wire's slack (cable ties spec 2026-10-26 §5.2): the pinned points (the ends and the lanes) are drawn exactly where
/// they are at every frame; only the wires whose pinned points moved go slack; a route that changed shape starts taut; at
/// rest nothing is held and the drawn route is the taut route bit for bit; time never runs backwards.
struct WireMotionTests {
    let upper = Endpoint(node: nodeID(3), socket: "value"), lower = Endpoint(node: nodeID(4), socket: "value")
    let before: [Endpoint: [Vector2]] = [
        Endpoint(node: nodeID(3), socket: "value"): [Vector2(168, 60), Vector2(384, 158), Vector2(600, 60)],
        Endpoint(node: nodeID(4), socket: "value"): [Vector2(168, 260), Vector2(600, 260)],
    ]
    let after: [Endpoint: [Vector2]] = [
        Endpoint(node: nodeID(3), socket: "value"): [Vector2(168, 60), Vector2(384, 198), Vector2(600, 60)],
        Endpoint(node: nodeID(4), socket: "value"): [Vector2(168, 260), Vector2(600, 260)],
    ]

    func moved() -> WireMotion {
        var motion = WireMotion()
        motion.excite(from: before, to: after, at: 10)
        return motion
    }

    @Test func aLaneThatMovesDownBowsBothItsPiecesUp() throws {
        let springs = try #require(moved().springs[upper])
        #expect(springs.count == 2)
        #expect(springs[0].control2.offset.y < 0 && springs[0].control1 == SpringPoint(), "the piece into the lane")
        #expect(springs[1].control1.offset.y < 0 && springs[1].control2 == SpringPoint(), "the piece out of it")
    }

    @Test func onlyTheWiresThatMovedGoSlack() {
        #expect(Set(moved().springs.keys) == [upper])
    }

    @Test func pinnedPointsAreExactOnEveryFrame() {
        let route = WireRoute(wire: upper, through: after[upper] ?? [], flow: .horizontal)
        let motion = moved()
        var bowed = false
        for frame in 0...40 {
            let drawn = motion.advanced(to: 10 + Double(frame) / 60).drawn(route)
            #expect(drawn.pinned == route.pinned, "frame \(frame)")
            if drawn != route { bowed = true }
        }
        #expect(bowed, "the pieces bowed in between")
        #expect(motion.advanced(to: 11).isAtRest)
        #expect(motion.advanced(to: 11).drawn(route) == route, "taut again, bit for bit")
    }

    @Test func aRouteThatChangedShapeStartsTaut() {
        var motion = moved()
        motion.excite(from: after, to: [upper: [Vector2(168, 60), Vector2(600, 60)], lower: after[lower] ?? []], at: 10.1)
        #expect(motion.springs[upper] == nil, "the tie went: two pieces became one")
    }

    @Test func timeNeverRunsBackwards() {
        let motion = moved()
        #expect(motion.advanced(to: 9) == motion)
        #expect(motion.advanced(to: 10) == motion)
    }

    @Test func atRestNothingIsDrawnDifferently() {
        let route = WireRoute(wire: lower, through: after[lower] ?? [], flow: .horizontal)
        #expect(WireMotion().drawn(route) == route)
        #expect(WireMotion().isAtRest)
    }
}
