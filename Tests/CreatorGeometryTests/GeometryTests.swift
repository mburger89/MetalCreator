import Testing
@testable import CreatorGeometry

func isClose(_ a: Double, _ b: Double, tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }
func isClose(_ a: Vector3, _ b: Vector3) -> Bool { (a - b).length <= 1e-9 }

struct VectorTests {
    @Test func crossProductOfAxesIsRightHanded() {
        #expect(Vector3.unitX.cross(.unitY) == .unitZ)
        #expect(Vector3.unitY.cross(.unitZ) == .unitX)
    }

    @Test func zeroVectorHasNoDirection() {
        #expect(Vector3.zero.normalized == nil)
        #expect(Vector3(3, 0, 4).normalized.map { isClose($0.length, 1) } == true)
    }

    @Test func nanIsNotFinite() {
        #expect(Vector3(1, .nan, 0).isFinite == false)
    }
}

struct PlaneTests {
    @Test(arguments: [Plane.xy, .xz, .yz])
    func yAxisCompletesARightHandedFrame(_ plane: Plane) {
        #expect(isClose(plane.xAxis.cross(plane.yAxis), plane.normal))
    }

    @Test func xzPlaneMapsLocalYToWorldZ() {
        #expect(isClose(Plane.xz.point(Vector2(2, 5)), Vector3(2, 0, 5)))
    }

    @Test func offsetMovesAlongNormal() {
        #expect(isClose(Plane.xy.offset(by: 3).origin, Vector3(0, 0, 3)))
    }
}

struct ProfileTests {
    @Test func rectangleIsClosedAndCentred() throws {
        let rect = Profile2D.rectangle(width: 60, height: 40, plane: .xy)
        #expect(rect.segments.count == 4)
        #expect(rect.isClosed)
        let bounds = try #require(rect.bounds)
        #expect(isClose(bounds.min, Vector3(-30, -20, 0)))
        #expect(isClose(bounds.max, Vector3(30, 20, 0)))
    }

    @Test func circleIsClosedWithOneArc() throws {
        let circle = Profile2D.circle(radius: 2.5, center: Vector2(10, 0), plane: .xy)
        #expect(circle.segments.count == 1)
        #expect(circle.isClosed)
        #expect(isClose(circle.segments[0].length, 2 * .pi * 2.5))
        let bounds = try #require(circle.bounds)
        #expect(isClose(bounds.min, Vector3(7.5, -2.5, 0)))
    }

    @Test func openPolylineIsNotClosed() {
        let open = Profile2D(plane: .xy, segments: [.line(Vector2(0, 0), Vector2(1, 0)), .line(Vector2(1, 0), Vector2(1, 1))])
        #expect(open.isClosed == false)
    }
}

struct BoundingBoxTests {
    @Test func emptyPointListHasNoBox() {
        #expect(BoundingBox(points: []) == nil)
    }

    @Test func disjointBoxesHaveNoIntersection() throws {
        let a = try #require(BoundingBox(points: [.zero, Vector3(1, 1, 1)]))
        let b = try #require(BoundingBox(points: [Vector3(2, 2, 2), Vector3(3, 3, 3)]))
        #expect(a.intersection(b) == nil)
        #expect(a.union(b).size == Vector3(3, 3, 3))
    }
}
