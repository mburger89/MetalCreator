import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

struct WireGeometryTests {
    @Test func horizontalWiresLeaveRightAndEnterFromTheLeft() {
        let wire = WireGeometry(from: Vector2(0, 0), to: Vector2(200, 50), flow: .horizontal)
        #expect(wire.control1 == Vector2(100, 0))
        #expect(wire.control2 == Vector2(100, 50))
    }

    @Test func verticalWiresLeaveDownAndEnterFromAbove() {
        let wire = WireGeometry(from: Vector2(0, 0), to: Vector2(30, 300), flow: .vertical)
        #expect(wire.control1 == Vector2(0, 150))
        #expect(wire.control2 == Vector2(30, 150))
    }

    @Test func backwardsWiresStillLoopOutOfTheirSockets() {
        let wire = WireGeometry(from: Vector2(200, 0), to: Vector2(0, 0), flow: .horizontal)
        #expect(wire.control1 == Vector2(300, 0))
        #expect(wire.control2 == Vector2(-100, 0))
        #expect(wire.bounds(padding: 4) == CanvasRect(origin: Vector2(-104, -4), size: Vector2(408, 8)))
    }

    @Test func shortWiresKeepAMinimumReach() {
        let wire = WireGeometry(from: Vector2(0, 0), to: Vector2(10, 0), flow: .horizontal)
        #expect(wire.control1 == Vector2(40, 0))
    }
}
