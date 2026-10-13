import CreatorGeometry
import Testing
@testable import CreatorNodes

/// A profile read as a region (`FaceRegion.outline(of:)`), the way Field Scatter reads one: outer loop and holes.
struct FaceRegionProfileTests {
    /// A 60 × 40 rectangle on the XY plane with a Ø20 hole (an arc over a full turn) at its centre.
    static let holed: Profile2D = {
        let corners = [Vector2(-30, -20), Vector2(30, -20), Vector2(30, 20), Vector2(-30, 20)]
        let outer = corners.indices.map { Segment2D.line(corners[$0], corners[($0 + 1) % 4]) }
        let hole = Segment2D.arc(center: .zero, radius: 10, start: Angle(radians: 0), end: Angle(radians: 2 * .pi))
        return Profile2D(plane: .xy, outer: outer, holes: [[hole]])
    }()

    @Test func theOuterLoopAndTheHoleBecomeTwoLoops() {
        let region = FaceRegion.outline(of: Self.holed)
        #expect(region.loops.count == 2 && region.loops[0].count == 4 && region.loops[1].count > 50)
        let box = region.bounds
        #expect(box?.min == Vector2(-30, -20) && box?.max == Vector2(30, 20))
    }

    @Test func theHoleIsOutsideTheRegionAndTheRingAroundItIsInside() {
        let region = FaceRegion.outline(of: Self.holed)
        #expect(!region.allows(.zero, margin: 0) && !region.allows(Vector2(9, 0), margin: 0))
        #expect(region.allows(Vector2(15, 0), margin: 2) && !region.allows(Vector2(11, 0), margin: 2), "2 mm clear of the hole's edge")
        #expect(!region.allows(Vector2(29, 0), margin: 2), "and of the outline")
    }

    @Test func aClockwiseArcIsChordedTheSameWay() {
        let arc = Segment2D.arc(center: .zero, radius: 5, start: Angle(radians: 2 * .pi), end: Angle(radians: 0))
        let region = FaceRegion.outline(of: Profile2D(plane: .xy, segments: [arc]))
        #expect(region.contains(Vector2(1, 1)) && !region.contains(Vector2(6, 0)))
    }
}
