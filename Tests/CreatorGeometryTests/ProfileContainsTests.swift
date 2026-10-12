import Foundation
import Testing
@testable import CreatorGeometry

/// Whether a point lies on a profile's region, for Cull by Region's profile mode.
struct ProfileContainsTests {
    let rectangle = Profile2D.rectangle(width: 20, height: 10, plane: .xy)

    @Test func aPointInsideARectangleIsIn() {
        #expect(rectangle.contains(Vector2(0, 0)))
        #expect(rectangle.contains(Vector2(9.9, 4.9)))
    }

    @Test func aPointOutsideARectangleIsOut() {
        #expect(!rectangle.contains(Vector2(10.1, 0)))
        #expect(!rectangle.contains(Vector2(0, -5.1)))
        #expect(!rectangle.contains(Vector2(-30, 40)))
    }

    @Test func aPointOnTheOutlineCountsAsInside() {
        #expect(rectangle.contains(Vector2(10, 0)))
        #expect(rectangle.contains(Vector2(-10, -5)), "a corner")
        #expect(rectangle.contains(Vector2(10 + 1e-7, 0)), "within the tolerance")
        #expect(!rectangle.contains(Vector2(10 + 1e-3, 0)))
    }

    @Test func aCircleIsFoundThroughItsArc() {
        let circle = Profile2D.circle(radius: 10, center: Vector2(5, 0), plane: .xy)
        #expect(circle.contains(Vector2(5, 0)))
        #expect(circle.contains(Vector2(14.9, 0)))
        #expect(!circle.contains(Vector2(15.1, 0)))
        #expect(!circle.contains(Vector2(5, 10.1)))
        #expect(circle.contains(Vector2(5 + 7, 7)), "inside at 45° (r = 9.9)")
        #expect(!circle.contains(Vector2(5 + 7.2, 7.2)), "outside at 45° (r = 10.18)")
    }

    @Test func aHoleIsOutsideTheRegion() {
        let hole: [Segment2D] = [.arc(center: Vector2(0, 0), radius: 2, start: Angle(radians: 0), end: Angle(radians: 2 * .pi))]
        let plate = Profile2D(plane: .xy, outer: rectangle.outer, holes: [hole])
        #expect(!plate.contains(Vector2(0, 0)), "in the hole")
        #expect(plate.contains(Vector2(3, 0)), "beside the hole")
        #expect(plate.contains(Vector2(2, 0)), "on the hole's edge")
        #expect(!plate.contains(Vector2(20, 0)))
    }

    @Test func anLShapedNotchIsHandled() {
        // An L-shaped notch: the region is the 20 × 10 rectangle without its top-right quarter.
        let corners = [Vector2(-10, -5), Vector2(10, -5), Vector2(10, 0), Vector2(0, 0), Vector2(0, 5), Vector2(-10, 5)]
        let loop = corners.indices.map { Segment2D.line(corners[$0], corners[($0 + 1) % corners.count]) }
        let profile = Profile2D(plane: .xy, segments: loop)
        #expect(profile.contains(Vector2(-5, 3)))
        #expect(profile.contains(Vector2(5, -3)))
        #expect(!profile.contains(Vector2(5, 3)), "in the notch")
    }

    @Test func anEmptyProfileContainsNothing() {
        #expect(!Profile2D(plane: .xy, outer: []).contains(Vector2(0, 0)))
    }
}
