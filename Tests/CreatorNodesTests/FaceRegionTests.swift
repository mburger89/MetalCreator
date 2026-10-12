import CreatorGeometry
import Foundation
import Testing
@testable import CreatorNodes

/// The outline Face Pattern clips to (patterns spec §3): even-odd containment, the distance to every edge, the inset guide.
struct FaceRegionTests {
    func square(_ low: Double, _ high: Double) -> [Vector2] {
        [Vector2(low, low), Vector2(high, low), Vector2(high, high), Vector2(low, high)]
    }

    var plate: FaceRegion { FaceRegion(loops: [square(0, 40)]) }
    var drilled: FaceRegion { FaceRegion(loops: [square(0, 40), square(15, 25)]) }

    @Test func aPointIsOnTheFaceInsideTheOutlineAndOutsideItsHoles() {
        #expect(plate.contains(Vector2(20, 20)) && !plate.contains(Vector2(41, 20)) && !plate.contains(Vector2(-1, 20)))
        #expect(drilled.contains(Vector2(5, 5)) && !drilled.contains(Vector2(20, 20)))
    }

    @Test func theDistanceToTheBoundaryCountsHolesToo() {
        #expect(isClose(plate.distanceToBoundary(Vector2(10, 20)), 10))
        #expect(isClose(drilled.distanceToBoundary(Vector2(10, 20)), 5), "the hole is nearer than the outline")
        #expect(isClose(plate.distanceToBoundary(Vector2(-3, 20)), 3), "measured from outside, too")
    }

    @Test func aMarginKeepsPlacementsClearOfEveryEdge() {
        #expect(plate.allows(Vector2(3, 20), margin: 3) && !plate.allows(Vector2(2.9, 20), margin: 3))
        #expect(drilled.allows(Vector2(12, 20), margin: 3) && !drilled.allows(Vector2(13, 20), margin: 3))
        #expect(plate.allows(Vector2(0.5, 20), margin: 0), "no margin only needs the face")
        #expect(!plate.allows(Vector2(-0.5, 20), margin: 0))
    }

    @Test func theBoundsEnclosEveryLoop() throws {
        let box = try #require(drilled.bounds)
        #expect(box.min == Vector2(0, 0) && box.max == Vector2(40, 40))
        #expect(FaceRegion(loops: []).bounds == nil)
    }

    @Test func aLoopOfFewerThanThreePointsIsNotAnOutline() {
        #expect(FaceRegion(loops: [[Vector2(0, 0), Vector2(1, 1)]]).loops.isEmpty)
    }

    @Test func theInsetGuideMovesTheOutlineInAndHolesOut() {
        let guide = drilled.insetOutline(margin: 3)
        func sorted(_ loop: [Vector2]) -> [Vector2] { loop.sorted { ($0.x, $0.y) < ($1.x, $1.y) } }
        #expect(sorted(guide[0]) == sorted(square(3, 37)))
        #expect(sorted(guide[1]) == sorted(square(12, 28)))
    }

    @Test func theInsetGuideDoesNotDependOnWhichWayALoopRuns() {
        let reversed = FaceRegion(loops: [square(0, 40).reversed(), square(15, 25).reversed()])
        let guide = reversed.insetOutline(margin: 3)
        #expect(Set(guide[0].map(\.x)) == [3, 37] && Set(guide[1].map(\.x)) == [12, 28])
    }

    @Test func noMarginGivesTheOutlineItself() {
        #expect(drilled.insetOutline(margin: 0) == drilled.loops)
    }
}
