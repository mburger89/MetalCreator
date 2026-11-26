import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

/// Where a symbol stands on an arc (DR-4 backlog): on the arc itself, never on the rest of its circle.
@Suite("Symbol foot")
struct SymbolFootTests {
    let frame = StandardOrientation.top.frame
    /// A quarter arc about the origin from (10, 0) counter-clockwise to (0, 10).
    let quarter = AnchorGeometry.circle(
        center: Vector3(0, 0, 0), axis: Vector3(0, 0, 1), radius: 10, start: Vector3(10, 0, 0), sweep: .pi / 2)

    func foot(_ geometry: AnchorGeometry, hint: Vector2) throws -> Vector2 {
        guard case .success(let found) = SymbolFoot.of(geometry, hint: hint, frame: frame) else {
            Issue.record("expected a foot")
            return .zero
        }
        return found.foot
    }

    @Test func aHintInsideTheSweepStandsRadiallyOutFromTheCentre() throws {
        let foot = try foot(quarter, hint: Vector2(14, 14))
        let half = 10 * (0.5).squareRoot()
        #expect((foot - Vector2(half, half)).length < 1e-9)
    }

    @Test func aHintBeforeTheStartStandsOnTheStart() throws {
        let foot = try foot(quarter, hint: Vector2(10, -10))
        #expect((foot - Vector2(10, 0)).length < 1e-9)
    }

    @Test func aHintPastTheEndStandsOnTheEnd() throws {
        let foot = try foot(quarter, hint: Vector2(-10, 10))
        #expect((foot - Vector2(0, 10)).length < 1e-9)
    }

    @Test func aFullCircleStaysUnchanged() throws {
        let full = AnchorGeometry.circle(
            center: Vector3(0, 0, 0), axis: Vector3(0, 0, 1), radius: 10, start: Vector3(10, 0, 0), sweep: 2 * .pi)
        let foot = try foot(full, hint: Vector2(-30, 0))
        #expect((foot - Vector2(-10, 0)).length < 1e-9)
    }

    @Test func aClockwiseSeenArcKeepsItsSide() throws {
        // The same arc seen from underneath runs clockwise on the sheet; the foot still lands on it.
        let flipped = AnchorGeometry.circle(
            center: Vector3(0, 0, 0), axis: Vector3(0, 0, -1), radius: 10, start: Vector3(10, 0, 0), sweep: .pi / 2)
        let foot = try foot(flipped, hint: Vector2(14, -14))
        let half = 10 * (0.5).squareRoot()
        #expect((foot - Vector2(half, -half)).length < 1e-9)
    }
}
