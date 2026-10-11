import Testing
@testable import CreatorGeometry

struct ProfileShapeTests {
    @Test func translatingMovesEverySegment() {
        let moved = Profile2D.circle(radius: 2, center: .zero, plane: .xy).translated(by: Vector2(3, 4))
        guard case .arc(let center, let radius, _, _) = moved.segments[0] else { Issue.record("expected an arc"); return }
        #expect(center == Vector2(3, 4))
        #expect(radius == 2)
        let line = Segment2D.line(Vector2(0, 0), Vector2(1, 0)).translated(by: Vector2(1, 1))
        #expect(line == .line(Vector2(1, 1), Vector2(2, 1)))
    }

    @Test func roundedRectangleIsAClosedEightSegmentLoop() {
        let profile = Profile2D.roundedRectangle(width: 60, height: 40, radius: 4, plane: .xy)
        #expect(profile.segments.count == 8)
        #expect(profile.isClosed)
        let perimeter = profile.segments.reduce(0) { $0 + $1.length }
        #expect(isClose(perimeter, 2 * (52 + 32) + 2 * Double.pi * 4, tolerance: 1e-9))
        guard case .line(let a, let b) = profile.segments[2] else { Issue.record("segment 2 is the right edge"); return }
        #expect(a.x == 30 && b.x == 30)
    }

    @Test func regularPolygonCornersLieOnTheCircle() {
        let hexagon = Profile2D.regularPolygon(sides: 6, radius: 10, plane: .xy)
        #expect(hexagon.segments.count == 6)
        #expect(hexagon.isClosed)
        #expect(hexagon.segments.allSatisfy { isClose($0.startPoint.length, 10) })
        #expect(isClose(hexagon.segments[0].startPoint.x, 10))
    }

    @Test func regularPolygonTurnsByItsRotation() {
        let hexagon = Profile2D.regularPolygon(sides: 6, radius: 10, rotation: .degrees(30), plane: .xy)
        #expect(hexagon.isClosed)
        #expect(isClose(hexagon.segments[0].startPoint.x, 10 * 3.0.squareRoot() / 2))
        #expect(isClose(hexagon.segments[0].startPoint.y, 5))
        let vertical = hexagon.segments.filter { abs($0.endPoint.x - $0.startPoint.x) < 1e-9 }
        #expect(vertical.count == 2, "a hexagon turned 30° has two sides parallel to y")
    }

    @Test func polylineClosesOnlyWhenAsked() {
        let points = [Vector2(0, 0), Vector2(10, 0), Vector2(0, 10)]
        #expect(Profile2D.polyline(points, closed: true, plane: .xy).isClosed)
        #expect(Profile2D.polyline(points, closed: true, plane: .xy).segments.count == 3)
        #expect(!Profile2D.polyline(points, closed: false, plane: .xy).isClosed)
        #expect(Profile2D.polyline(points, closed: false, plane: .xy).segments.count == 2)
    }
}

struct ProfileSlotTests {
    @Test func aSlotIsAClosedFourSegmentLoopCentredOnTheOrigin() {
        let slot = Profile2D.slot(length: 20, width: 6, plane: .xy)
        #expect(slot.segments.count == 4)
        #expect(slot.isClosed)
        #expect(slot.bounds?.min == Vector3(-10, -3, 0))
        #expect(slot.bounds?.max == Vector3(10, 3, 0))
    }

    @Test func aSlotsPerimeterIsTwoStraightsAndACircle() {
        let slot = Profile2D.slot(length: 20, width: 6, plane: .xy)
        #expect(isClose(slot.segments.reduce(0) { $0 + $1.length }, 2 * 14 + 2 * Double.pi * 3, tolerance: 1e-9))
    }

    @Test func aSlotsEndsAreRoundedAboutTheCentresOfItsEnds() {
        let slot = Profile2D.slot(length: 20, width: 6, plane: .xy)
        guard case .arc(let right, let radius, _, _) = slot.segments[1], case .arc(let left, _, _, _) = slot.segments[3] else {
            Issue.record("segments 1 and 3 are the ends' arcs")
            return
        }
        #expect(right == Vector2(7, 0) && left == Vector2(-7, 0) && radius == 3)
    }
}
