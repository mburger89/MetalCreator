import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("Projected view rule")
struct ProjectedViewRuleTests {
    private let front = StandardOrientation.front.frame

    private func check(
        _ offset: Vector2, _ standard: DrawingStandard, direction: Vector3, up: Vector3, axis: AlignmentAxis
    ) {
        let result = ProjectedViewRule.view(from: front, dropOffset: offset, standard: standard)
        #expect(result.frame.direction == direction)
        #expect(result.frame.up == up)
        #expect(result.axis == axis)
    }

    @Test func firstAngleCases() {
        check(Vector2(50, 0), .iso, direction: Vector3(1, 0, 0), up: Vector3(0, 0, 1), axis: .horizontal)
        check(Vector2(-50, 0), .iso, direction: Vector3(-1, 0, 0), up: Vector3(0, 0, 1), axis: .horizontal)
        check(Vector2(0, 50), .iso, direction: Vector3(0, 0, 1), up: Vector3(0, -1, 0), axis: .vertical)
        check(Vector2(0, -50), .iso, direction: Vector3(0, 0, -1), up: Vector3(0, 1, 0), axis: .vertical)
    }

    @Test func thirdAngleCases() {
        check(Vector2(50, 0), .asme, direction: Vector3(-1, 0, 0), up: Vector3(0, 0, 1), axis: .horizontal)
        check(Vector2(-50, 0), .asme, direction: Vector3(1, 0, 0), up: Vector3(0, 0, 1), axis: .horizontal)
        check(Vector2(0, 50), .asme, direction: Vector3(0, 0, -1), up: Vector3(0, 1, 0), axis: .vertical)
        check(Vector2(0, -50), .asme, direction: Vector3(0, 0, 1), up: Vector3(0, -1, 0), axis: .vertical)
    }

    @Test func aDiagonalDropTakesTheLargerOffset() {
        let wide = ProjectedViewRule.view(from: front, dropOffset: Vector2(60, 40), standard: .iso)
        #expect(wide.axis == .horizontal)
        let tall = ProjectedViewRule.view(from: front, dropOffset: Vector2(40, 60), standard: .iso)
        #expect(tall.axis == .vertical)
    }

    @Test func anIsometricParentIsRefused() {
        let iso = DrawingView(
            kind: .base, source: NodeID(), orientation: .standard(.isometricFrontRight), center: .zero)
        #expect(
            ProjectedViewRule.refusal(for: iso)
                == "A projected view comes from a front, side, top or bottom view, not an isometric one.")
        let plain = DrawingView(kind: .base, source: NodeID(), orientation: .standard(.front), center: .zero)
        #expect(ProjectedViewRule.refusal(for: plain) == nil)
    }
}
