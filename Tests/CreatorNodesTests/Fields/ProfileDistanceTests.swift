import CreatorGeometry
import Testing
@testable import CreatorNodes

/// A profile's distance (fields spec §3.1): to its loops on its plane, not to its area, measured in 3D.
struct ProfileDistanceTests {
    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    @Test func aRectangleIsMeasuredToItsEdgesNotItsArea() {
        let distance = ProfileDistance(.rectangle(width: 10, height: 10, plane: .xy))
        #expect(near(distance.distance(from: Vector3(0, 0, 0)), 5), "the centre is 5 mm from every edge")
        #expect(near(distance.distance(from: Vector3(5, 2, 0)), 0), "on an edge")
        #expect(near(distance.distance(from: Vector3(8, 0, 0)), 3))
        #expect(near(distance.distance(from: Vector3(8, 8, 0)), 18.0.squareRoot()), "past a corner it is the corner")
    }

    @Test func theHeightAboveThePlaneCounts() {
        let distance = ProfileDistance(.rectangle(width: 10, height: 10, plane: .xy))
        #expect(near(distance.distance(from: Vector3(0, 0, 4)), 41.0.squareRoot()))
        #expect(near(distance.distance(from: Vector3(8, 0, 3)), 18.0.squareRoot()))
        #expect(near(distance.distance(from: Vector3(5, 0, -2)), 2))
    }

    @Test func aPlaneThatIsNotTheGroundPlaneIsRespected() {
        let distance = ProfileDistance(.rectangle(width: 10, height: 10, plane: Plane.xz.offset(by: 7)))
        // Plane.xz faces -Y; offset 7 puts the plane at y = -7. The point is 2 mm in front of it and 3 mm outside the edge.
        #expect(near(distance.distance(from: Vector3(8, -9, 0)), 13.0.squareRoot()))
        #expect(near(distance.distance(from: Vector3(0, -7, 0)), 5))
    }

    @Test func aCircleIsMeasuredToItsRim() {
        let distance = ProfileDistance(.circle(radius: 3, center: .zero, plane: .xy))
        #expect(near(distance.distance(from: Vector3(5, 0, 0)), 2))
        #expect(near(distance.distance(from: Vector3(0, 0, 0)), 3), "from the centre every rim point is 3 away")
        #expect(near(distance.distance(from: Vector3(0, 4, 3)), 10.0.squareRoot()))
        #expect(near(distance.distance(from: Vector3(3, 0, 0)), 0))
    }

    @Test func anArcIsMeasuredToTheCircleWithinItsSweepAndToItsEndsOutside() {
        let half: [Segment2D] = [
            .arc(center: .zero, radius: 2, start: .degrees(0), end: .degrees(180)),
            .line(Vector2(-2, 0), Vector2(2, 0)),
        ]
        let distance = ProfileDistance(Profile2D(plane: .xy, segments: half))
        #expect(near(distance.distance(from: Vector3(0, 3, 0)), 1), "above the arc: straight out to the circle")
        #expect(near(distance.distance(from: Vector3(0, -1, 0)), 1), "below: the straight edge is 1 away")
        #expect(near(distance.distance(from: Vector3(0, 0, 0)), 0), "on the straight edge")
        #expect(near(distance.distance(from: Vector3(0, 0.5, 0)), 0.5), "the straight edge is nearer than the arc, 1.5 away")
    }

    @Test func aClockwiseArcCoversTheSameCircleAsItsCounterClockwiseTwin() {
        let clockwise: [Segment2D] = [
            .arc(center: .zero, radius: 2, start: .degrees(180), end: .degrees(0)),
            .line(Vector2(2, 0), Vector2(-2, 0)),
        ]
        let counter: [Segment2D] = [
            .arc(center: .zero, radius: 2, start: .degrees(0), end: .degrees(180)),
            .line(Vector2(-2, 0), Vector2(2, 0)),
        ]
        let a = ProfileDistance(Profile2D(plane: .xy, segments: clockwise)), b = ProfileDistance(Profile2D(plane: .xy, segments: counter))
        for point in [Vector3(0, 3, 0), Vector3(0, -1, 2), Vector3(3, 3, 0), Vector3(-1, 1, 1)] {
            #expect(near(a.distance(from: point), b.distance(from: point)))
        }
    }

    @Test func aHolesLoopCounts() {
        let outer = Profile2D.rectangle(width: 20, height: 20, plane: .xy).outer
        let hole = Profile2D.circle(radius: 2, center: .zero, plane: .xy).outer
        let distance = ProfileDistance(Profile2D(plane: .xy, outer: outer, holes: [hole]))
        #expect(near(distance.distance(from: Vector3(0, 0, 0)), 2), "the hole's rim is nearer than the outline")
        #expect(near(distance.distance(from: Vector3(7, 0, 0)), 3), "7 is 3 from the outline at x = 10 and 5 from the hole")
    }
}
