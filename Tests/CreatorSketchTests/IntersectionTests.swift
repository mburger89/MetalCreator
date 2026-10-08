import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// Exact curve intersections and curve-shape helpers (spec §5 step 2).
struct IntersectionTests {
    func circle(_ center: Vector2, _ radius: Double) -> CurveShape {
        .arc(center: center, radius: radius, start: 0, sweep: 2 * .pi)
    }

    func sorted(_ points: [Vector2]) -> [Vector2] {
        points.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
    }

    @Test func crossingLinesMeetOnce() {
        let points = CurveIntersection.points(.line(.zero, Vector2(10, 10)), .line(Vector2(0, 10), Vector2(10, 0)))
        #expect(points.count == 1)
        #expect(isClose(points[0], Vector2(5, 5), tolerance: 1e-12))
    }

    @Test func linesThatWouldCrossBeyondTheirEndsDoNot() {
        #expect(CurveIntersection.points(.line(.zero, Vector2(4, 0)), .line(Vector2(5, -1), Vector2(5, 1))).isEmpty)
    }

    @Test func parallelLinesNeverMeet() {
        #expect(CurveIntersection.points(.line(.zero, Vector2(10, 0)), .line(Vector2(0, 1), Vector2(10, 1))).isEmpty)
    }

    @Test func overlappingCollinearLinesMeetAtTheOverlapEnds() {
        let points = CurveIntersection.points(.line(.zero, Vector2(10, 0)), .line(Vector2(4, 0), Vector2(15, 0)))
        #expect(sorted(points) == [Vector2(4, 0), Vector2(10, 0)])
    }

    @Test func aTJunctionMeetsAtTheStemsEnd() {
        let points = CurveIntersection.points(.line(.zero, Vector2(10, 0)), .line(Vector2(3, 0), Vector2(3, 7)))
        #expect(points == [Vector2(3, 0)])
    }

    @Test func lineThroughACircleMeetsItTwice() {
        let points = sorted(CurveIntersection.points(.line(Vector2(-10, 3), Vector2(10, 3)), circle(.zero, 5)))
        #expect(points.count == 2)
        #expect(isClose(points[0], Vector2(-4, 3), tolerance: 1e-12))
        #expect(isClose(points[1], Vector2(4, 3), tolerance: 1e-12))
    }

    @Test func tangentLineTouchesOnce() {
        let points = CurveIntersection.points(.line(Vector2(-10, 5), Vector2(10, 5)), circle(.zero, 5))
        #expect(points.count == 1)
        #expect(isClose(points[0], Vector2(0, 5), tolerance: 1e-12))
    }

    @Test func anArcOnlyMeetsWithinItsSpan() {
        // The upper half only: the line y = −3 misses it; y = 3 meets it twice.
        let upper = CurveShape.arc(center: .zero, radius: 5, start: 0, sweep: .pi)
        #expect(CurveIntersection.points(.line(Vector2(-10, -3), Vector2(10, -3)), upper).isEmpty)
        #expect(CurveIntersection.points(.line(Vector2(-10, 3), Vector2(10, 3)), upper).count == 2)
    }

    @Test func circlesMeetTwiceOnceOrNever() {
        let two = sorted(CurveIntersection.points(circle(.zero, 5), circle(Vector2(8, 0), 5)))
        #expect(two.count == 2)
        #expect(isClose(two[0], Vector2(4, -3), tolerance: 1e-12))
        #expect(isClose(two[1], Vector2(4, 3), tolerance: 1e-12))
        let touching = CurveIntersection.points(circle(.zero, 3), circle(Vector2(5, 0), 2))
        #expect(touching.count == 1)
        #expect(isClose(touching[0], Vector2(3, 0), tolerance: 1e-12))
        #expect(CurveIntersection.points(circle(.zero, 5), circle(Vector2(1, 0), 1)).isEmpty)
        #expect(CurveIntersection.points(circle(.zero, 5), circle(.zero, 3)).isEmpty)
    }

    @Test func coCircularArcsMeetAtTheirOverlapEnds() {
        let first = CurveShape.arc(center: .zero, radius: 5, start: 0, sweep: .pi)
        let second = CurveShape.arc(center: .zero, radius: 5, start: .pi / 2, sweep: .pi)
        let points = sorted(CurveIntersection.points(first, second))
        #expect(points.count == 2)
        #expect(isClose(points[0], Vector2(-5, 0), tolerance: 1e-9))
        #expect(isClose(points[1], Vector2(0, 5), tolerance: 1e-9))
    }

    @Test func shapeParametersAndPieces() {
        let arc = CurveShape.arc(center: Vector2(1, 1), radius: 2, start: .pi / 2, sweep: .pi)
        #expect(isClose(arc.startPoint, Vector2(1, 3), tolerance: 1e-12))
        #expect(isClose(arc.endPoint, Vector2(1, -1), tolerance: 1e-12))
        #expect(isClose(arc.parameter(of: Vector2(-1, 1)), .pi / 2, tolerance: 1e-12))
        // A point outside the span clamps to the nearer end.
        #expect(arc.nearestParameter(to: Vector2(3, 1.5)) == 0)
        #expect(arc.contains(Vector2(-1, 1), tolerance: 1e-9))
        #expect(!arc.contains(Vector2(3, 1), tolerance: 1e-9))
        let piece = CurveShape.line(.zero, Vector2(10, 0)).piece(from: 0.2, to: 0.5)
        #expect(piece == .line(Vector2(2, 0), Vector2(5, 0)))
        #expect(isClose(arc.tangent(at: 0), Vector2(-1, 0), tolerance: 1e-12))
    }

    @Test func sketchShapesComeFromCurrentPositions() throws {
        var sketch = Sketch()
        let center = sketch.addPoint(.zero)
        let start = sketch.addPoint(Vector2(0, 5))
        // From 90° counter-clockwise round to 0°: a three-quarter arc.
        let arc = sketch.addArc(center: center, start: start, end: sketch.addPoint(Vector2(5, 0)))
        guard case .arc(_, let radius, let from, let sweep)? = sketch.shape(of: arc) else {
            Issue.record("no arc shape")
            return
        }
        #expect(radius == 5)
        #expect(isClose(from, .pi / 2, tolerance: 1e-12))
        #expect(isClose(sweep, 3 * .pi / 2, tolerance: 1e-12))
        sketch.solved[start] = .point(Vector2(-5, 0))
        guard case .arc(_, _, _, let moved)? = sketch.shape(of: arc) else {
            Issue.record("no arc shape")
            return
        }
        #expect(isClose(moved, .pi, tolerance: 1e-12))
        let suspended = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(.zero, Vector2(1, 0)),
                                                                          isSuspended: true))))
        #expect(sketch.shape(of: suspended) == nil)
        #expect(sketch.shape(of: center) == nil)
    }
}
