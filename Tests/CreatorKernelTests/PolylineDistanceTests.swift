import CreatorGeometry
import Testing
@testable import CreatorKernel

/// `PolylineDistance`: points and outlines measured in Swift (Measure follow-ups, Ruling 2).
struct PolylineDistanceTests {
    func distance(_ a: MeasureElement, _ b: MeasureElement) throws -> ShapeDistance {
        try #require(PolylineDistance.shortest(a, b))
    }

    @Test func pointToPoint() throws {
        let found = try distance(.point(.zero), .point(Vector3(3, 4, 0)))
        #expect(found.distance == 5 && found.from == .zero && found.to == Vector3(3, 4, 0))
    }

    @Test func pointOnAPolylineIsZero() throws {
        let line = MeasureElement.polyline([.zero, Vector3(10, 0, 0), Vector3(10, 10, 0)])
        let point = Vector3(10, 4, 0)
        for found in [try distance(.point(point), line), try distance(line, .point(point))] {
            #expect(found.distance < 1e-12 && (found.from - point).length < 1e-12 && (found.to - point).length < 1e-12)
        }
    }

    @Test func pointToASegmentInterior() throws {
        let line = MeasureElement.polyline([.zero, Vector3(10, 0, 0)])
        let found = try distance(.point(Vector3(4, 3, 0)), line)
        #expect(abs(found.distance - 3) < 1e-12 && found.from == Vector3(4, 3, 0) && (found.to - Vector3(4, 0, 0)).length < 1e-12)
        let flipped = try distance(line, .point(Vector3(4, 3, 0)))
        #expect((flipped.from - Vector3(4, 0, 0)).length < 1e-12 && flipped.to == Vector3(4, 3, 0))
    }

    @Test func pointToAVertex() throws {
        let line = MeasureElement.polyline([.zero, Vector3(10, 0, 0), Vector3(10, 10, 0)])
        let found = try distance(.point(Vector3(13, -4, 0)), line)
        #expect(abs(found.distance - 5) < 1e-12 && found.to == Vector3(10, 0, 0))
    }

    @Test func crossingPolylinesAreZero() throws {
        let one = MeasureElement.polyline([Vector3(-5, 0, 0), Vector3(5, 0, 0)])
        let other = MeasureElement.polyline([Vector3(0, -5, 0), Vector3(0, 5, 0)])
        let found = try distance(one, other)
        #expect(found.distance < 1e-12 && (found.from - found.to).length < 1e-12)
    }

    @Test func parallelOverlappingSegments() throws {
        let one = MeasureElement.polyline([.zero, Vector3(10, 0, 0)])
        let other = MeasureElement.polyline([Vector3(4, 3, 0), Vector3(14, 3, 0)])
        let found = try distance(one, other)
        #expect(abs(found.distance - 3) < 1e-12)
        #expect(abs(found.from.y) < 1e-12 && found.from.x >= -1e-12 && found.from.x <= 10 + 1e-12)
        #expect(abs(found.to.y - 3) < 1e-12 && found.to.x >= 4 - 1e-12 && found.to.x <= 14 + 1e-12)
        #expect(abs((found.from - found.to).length - found.distance) < 1e-12)
    }

    @Test func aClosedPolylineIncludesItsClosingSegment() throws {
        let square = MeasureElement.polyline([.zero, Vector3(10, 0, 0), Vector3(10, 10, 0), Vector3(0, 10, 0), .zero])
        let found = try distance(.point(Vector3(-2, 5, 0)), square)
        #expect(abs(found.distance - 2) < 1e-12 && abs(found.to.x) < 1e-12 && abs(found.to.y - 5) < 1e-12)
    }

    @Test func aCurveDefersToTheKernel() {
        let curve = MeasureElement.curve(.line(start: .zero, end: Vector3(1, 0, 0)))
        #expect(PolylineDistance.shortest(curve, .point(.zero)) == nil)
        #expect(PolylineDistance.shortest(.point(.zero), curve) == nil)
        #expect(PolylineDistance.shortest(.polyline([.zero]), .point(.zero)) == nil)
    }

    @Test func overThePairLimitDefers() {
        let long = MeasureElement.polyline((0...600).map { Vector3(Double($0), 0, 0) })
        #expect(PolylineDistance.shortest(long, long) == nil)
        #expect(PolylineDistance.shortest(long, .point(.zero)) != nil)
    }
}
