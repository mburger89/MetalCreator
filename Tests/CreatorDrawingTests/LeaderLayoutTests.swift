import CreatorGeometry
import Testing

@testable import CreatorDrawing

@Suite("Leader layout")
struct LeaderLayoutTests {
    private let h = LayoutSupport.h
    private let hole = DimensionLabel(lines: [[.text("Ø6 THRU")], [.text("second")]])

    private func callout(angle: Double) -> AnnotationDrawing {
        SheetDimensionLayout.callout(
            center: Vector2(50, 50), radius: 3, lines: hole, placement: DimensionPlacement(offset: 10, angle: angle),
            mapping: LayoutSupport.identity, standard: .iso, height: h)
    }

    @Test func aCalloutLeaderEndsInAShoulder() {
        let right = callout(angle: 0)
        #expect(LayoutSupport.hasLine(right, Vector2(63, 50), Vector2(66, 50)))
        #expect(LayoutSupport.close(right.fills[0][0], Vector2(53, 50)))
        #expect(right.texts.count == 2)
        #expect(right.texts[0].origin.x >= 66)
        #expect(LayoutSupport.close(right.texts[0].origin.y - right.texts[1].origin.y, 1.6 * h))
        #expect(LayoutSupport.close(right.texts[0].origin.x, right.texts[1].origin.x))
        let left = callout(angle: .pi)
        #expect(LayoutSupport.hasLine(left, Vector2(37, 50), Vector2(34, 50), 1e-9))
        #expect(left.texts.allSatisfy { $0.origin.x + $0.run.width <= 34 + 1e-9 })
    }

    @Test func aNoteLeaderLeavesTheNearerSide() {
        // The caller picks the side from the leader's direction; a knee right of the tip shoulders to the right.
        let style = AnnotationStyle.of(.iso)
        let tip = Vector2(50, 60), knee = Vector2(90, 80)
        let drawing = SheetDimensionLayout.leader(tip: tip, knee: knee, side: .toward(knee - tip), style: style)
        #expect(LayoutSupport.hasLine(drawing, tip, knee))
        #expect(LayoutSupport.hasLine(drawing, knee, Vector2(93, 80)))
        #expect(drawing.fills.count == 1 && drawing.fills[0][0] == tip)
        let base = Vector2((drawing.fills[0][1].x + drawing.fills[0][2].x) / 2, (drawing.fills[0][1].y + drawing.fills[0][2].y) / 2)
        #expect(LayoutSupport.close((base - tip).length, style.arrowLength))
        #expect((base - tip).x > 0)
    }

    @Test func shoulderSideFollowsTheLeader() {
        #expect(ShoulderSide.toward(Vector2(-1, 2)) == .left)
        #expect(ShoulderSide.toward(Vector2(0, 1)) == .right)
        #expect(ShoulderSide.toward(Vector2(1, -1)) == .right)
        let drawing = SheetDimensionLayout.leader(
            tip: Vector2(10, 10), knee: Vector2(0, 20), side: .left, style: AnnotationStyle.of(.iso))
        #expect(LayoutSupport.hasLine(drawing, Vector2(0, 20), Vector2(-3, 20)))
    }

    @Test func aChamferLeaderTipsTheEdgeMiddle() {
        let drawing = SheetDimensionLayout.draw(
            .chamfer(start: Vector2(0, 0), end: Vector2(10, 10)), kind: .chamfer, labels: [LayoutSupport.label("C2")],
            placement: DimensionPlacement(offset: 8, angle: 0), mapping: LayoutSupport.identity, standard: .iso, height: h)
        #expect(LayoutSupport.close(drawing.fills[0][0], Vector2(5, 5)))
        #expect(drawing.texts.count == 1 && drawing.texts[0].angle == 0)
    }
}
