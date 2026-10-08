import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// One analytic fixture per constraint and dimension kind (spec §10). Each starts off the answer,
/// solves, and checks the defining property and, where the solver's minimal step makes it exact,
/// the resulting position.
struct ConstraintFixtureTests {
    /// Solves and requires the constraints to be met.
    func solved(_ sketch: Sketch) throws -> SketchSolution {
        let solution = SketchSolver.solve(sketch)
        try #require(solution.status.isUsable, "status \(solution.status)")
        return solution
    }

    /// A point fixed where drawn.
    func fixedPoint(_ sketch: inout Sketch, _ position: Vector2) -> SketchEntityID {
        let point = sketch.addPoint(position)
        sketch.add(.fix(point, at: position))
        return point
    }

    /// A line whose two endpoints are fixed where drawn.
    func fixedLine(_ sketch: inout Sketch, _ a: Vector2, _ b: Vector2) -> SketchEntityID {
        let line = sketch.addLine(from: fixedPoint(&sketch, a), to: fixedPoint(&sketch, b))
        return line
    }

    @Test func coincidentMovesTheFreePointOntoTheFixedOne() throws {
        var sketch = Sketch()
        let anchor = fixedPoint(&sketch, Vector2(2, 3))
        let free = sketch.addPoint(Vector2(5, -1))
        sketch.add(.coincident(free, anchor))
        let solution = try solved(sketch)
        #expect(isClose(try #require(solution.points[free]), Vector2(2, 3)))
    }

    @Test func pointOnLineDropsPerpendicularlyOntoIt() throws {
        var sketch = Sketch()
        let line = fixedLine(&sketch, .zero, Vector2(10, 0))
        let point = sketch.addPoint(Vector2(4, 3))
        sketch.add(.pointOn(point: point, curve: line))
        let solved = try #require(try solved(sketch).points[point])
        #expect(isClose(solved.y, 0))
        #expect(isNear(solved, Vector2(4, 0)))
    }

    @Test func pointOnCircleMovesRadially() throws {
        var sketch = Sketch()
        let center = fixedPoint(&sketch, .zero)
        let circle = sketch.addCircle(center: center, radius: 5)
        sketch.addDimension(.radius(circle), value: 5)
        let point = sketch.addPoint(Vector2(6, 8))
        sketch.add(.pointOn(point: point, curve: circle))
        #expect(isClose(try #require(try solved(sketch).points[point]), Vector2(3, 4)))
    }

    @Test func pointOnArcUsesItsCircle() throws {
        var sketch = Sketch()
        let center = fixedPoint(&sketch, .zero)
        let arc = sketch.addArc(center: center, start: fixedPoint(&sketch, Vector2(5, 0)), end: fixedPoint(&sketch, Vector2(0, 5)))
        // (−8, −6) is outside the arc's span: the constraint is on its full circle.
        let point = sketch.addPoint(Vector2(-8, -6))
        sketch.add(.pointOn(point: point, curve: arc))
        let solved = try #require(try solved(sketch).points[point])
        #expect(isClose(solved.length, 5))
        #expect(isNear(solved, Vector2(-4, -3)))
    }

    @Test func horizontalAndVerticalLines() throws {
        var sketch = Sketch()
        let start = fixedPoint(&sketch, .zero)
        let flat = sketch.addLine(from: start, to: sketch.addPoint(Vector2(10, 2)))
        let upright = sketch.addLine(from: start, to: sketch.addPoint(Vector2(-1, 7)))
        sketch.add(.horizontal(flat))
        sketch.add(.vertical(upright))
        let solution = try solved(sketch)
        // The line constraints are angle-based, so each end swings about the fixed start.
        let flatEnd = try #require(solution.points[sketch.ends(flat).1])
        let uprightEnd = try #require(solution.points[sketch.ends(upright).1])
        #expect(isClose(flatEnd.y, 0))
        #expect(flatEnd.x > 9)
        #expect(isClose(uprightEnd.x, 0))
        #expect(uprightEnd.y > 6)
    }

    @Test func horizontalAndVerticalPoints() throws {
        var sketch = Sketch()
        let anchor = fixedPoint(&sketch, Vector2(1, 1))
        let level = sketch.addPoint(Vector2(9, 4))
        let plumb = sketch.addPoint(Vector2(3, -6))
        sketch.add(.horizontalPoints(anchor, level))
        sketch.add(.verticalPoints(plumb, anchor))
        let solution = try solved(sketch)
        #expect(isClose(try #require(solution.points[level]), Vector2(9, 1)))
        #expect(isClose(try #require(solution.points[plumb]), Vector2(1, -6)))
    }

    @Test func parallelAndPerpendicular() throws {
        var sketch = Sketch()
        let reference = fixedLine(&sketch, .zero, Vector2(10, 0))
        let start = fixedPoint(&sketch, Vector2(0, 5))
        let parallel = sketch.addLine(from: start, to: sketch.addPoint(Vector2(10, 7)))
        let perpendicular = sketch.addLine(from: start, to: sketch.addPoint(Vector2(1, 12)))
        sketch.add(.parallel(reference, parallel))
        sketch.add(.perpendicular(perpendicular, reference))
        let solution = try solved(sketch)
        #expect(isClose(try #require(solution.points[sketch.ends(parallel).1]).y, 5))
        #expect(isClose(try #require(solution.points[sketch.ends(perpendicular).1]).x, 0))
    }

    @Test func tangentCircleMovesToTouchTheLine() throws {
        var sketch = Sketch()
        let line = fixedLine(&sketch, .zero, Vector2(20, 0))
        let circle = sketch.addCircle(center: fixedPoint(&sketch, Vector2(8, 3)), radius: 5)
        sketch.add(.tangent(line, circle))
        let solution = try solved(sketch)
        // The centre is fixed, so the radius shrinks to the distance to the line.
        #expect(isClose(try #require(solution.radii[circle]), 3))
    }

    @Test func tangentArcAtASharedEndpointHasItsRadiusPerpendicularToTheLine() throws {
        var sketch = Sketch()
        let corner = fixedPoint(&sketch, Vector2(10, 0))
        let line = sketch.addLine(from: fixedPoint(&sketch, .zero), to: corner)
        let center = sketch.addPoint(Vector2(11, 4))
        let arc = sketch.addArc(center: center, start: corner, end: sketch.addPoint(Vector2(15, 4)))
        sketch.add(.tangent(line, arc))
        let solution = try solved(sketch)
        let c = try #require(solution.points[center])
        #expect(isClose(c.x, 10))
    }

    @Test func externallyTangentCircles() throws {
        var sketch = Sketch()
        let first = sketch.addCircle(center: fixedPoint(&sketch, .zero), radius: 3)
        sketch.addDimension(.radius(first), value: 3)
        let second = sketch.addCircle(center: fixedPoint(&sketch, Vector2(10, 0)), radius: 4)
        sketch.add(.tangent(first, second))
        #expect(isClose(try #require(try solved(sketch).radii[second]), 7))
    }

    @Test func internallyTangentCircles() throws {
        var sketch = Sketch()
        let outer = sketch.addCircle(center: fixedPoint(&sketch, .zero), radius: 10)
        sketch.addDimension(.radius(outer), value: 10)
        let inner = sketch.addCircle(center: fixedPoint(&sketch, Vector2(4, 0)), radius: 5)
        sketch.add(.tangent(inner, outer))
        #expect(isClose(try #require(try solved(sketch).radii[inner]), 6))
    }

    @Test func equalLengthsAndRadii() throws {
        var sketch = Sketch()
        let reference = fixedLine(&sketch, .zero, Vector2(6, 8))
        let start = fixedPoint(&sketch, Vector2(0, 20))
        let copy = sketch.addLine(from: start, to: sketch.addPoint(Vector2(3, 20)))
        sketch.add(.equal(reference, copy))
        let big = sketch.addCircle(center: fixedPoint(&sketch, Vector2(30, 0)), radius: 4)
        sketch.addDimension(.radius(big), value: 4)
        let small = sketch.addCircle(center: fixedPoint(&sketch, Vector2(40, 0)), radius: 1)
        sketch.add(.equal(small, big))
        let solution = try solved(sketch)
        #expect(isClose(try #require(solution.points[sketch.ends(copy).1]), Vector2(10, 20)))
        #expect(isClose(try #require(solution.radii[small]), 4))
    }

    @Test func midpoint() throws {
        var sketch = Sketch()
        let line = fixedLine(&sketch, Vector2(2, 2), Vector2(8, 6))
        let point = sketch.addPoint(.zero)
        sketch.add(.midpoint(point: point, line: line))
        #expect(isClose(try #require(try solved(sketch).points[point]), Vector2(5, 4)))
    }

    @Test func concentricMovesTheFreeCentre() throws {
        var sketch = Sketch()
        let first = sketch.addCircle(center: fixedPoint(&sketch, Vector2(3, 3)), radius: 2)
        let freeCenter = sketch.addPoint(Vector2(5, 0))
        let second = sketch.addCircle(center: freeCenter, radius: 4)
        sketch.add(.concentric(second, first))
        #expect(isClose(try #require(try solved(sketch).points[freeCenter]), Vector2(3, 3)))
    }

    @Test func symmetricAboutAVerticalLine() throws {
        var sketch = Sketch()
        let axis = fixedLine(&sketch, Vector2(5, 0), Vector2(5, 10))
        let left = fixedPoint(&sketch, Vector2(2, 3))
        let right = sketch.addPoint(Vector2(9, 5))
        sketch.add(.symmetric(left, right, about: axis))
        #expect(isClose(try #require(try solved(sketch).points[right]), Vector2(8, 3)))
    }

    @Test func fixHoldsThePointWhereItSays() throws {
        var sketch = Sketch()
        let point = sketch.addPoint(Vector2(1, 1))
        sketch.add(.fix(point, at: Vector2(-4, 2.5)))
        #expect(isClose(try #require(try solved(sketch).points[point]), Vector2(-4, 2.5)))
    }

    @Test func pointToPointAndPointToLineDistances() throws {
        var sketch = Sketch()
        let origin = fixedPoint(&sketch, .zero)
        let far = sketch.addPoint(Vector2(3, 4))
        sketch.addDimension(.distance(origin, far), value: 10)
        let line = fixedLine(&sketch, Vector2(0, -10), Vector2(10, -10))
        let above = sketch.addPoint(Vector2(4, -7))
        sketch.addDimension(.distance(line, above), value: 5)
        let solution = try solved(sketch)
        #expect(isClose(try #require(solution.points[far]), Vector2(6, 8)))
        // It stays on the side of the line it was drawn on.
        let solvedAbove = try #require(solution.points[above])
        #expect(isClose(solvedAbove.y, -5))
        #expect(isNear(solvedAbove, Vector2(4, -5)))
    }

    @Test func lengthRadiusAndDiameter() throws {
        var sketch = Sketch()
        let line = sketch.addLine(from: fixedPoint(&sketch, .zero), to: sketch.addPoint(Vector2(3, 4)))
        sketch.addDimension(.length(line), value: 15)
        let circle = sketch.addCircle(center: fixedPoint(&sketch, Vector2(30, 0)), radius: 2)
        sketch.addDimension(.diameter(circle), value: 9)
        let center = fixedPoint(&sketch, Vector2(50, 0))
        let start = sketch.addPoint(Vector2(53, 0))
        let arc = sketch.addArc(center: center, start: start, end: sketch.addPoint(Vector2(50, 3)))
        sketch.addDimension(.radius(arc), value: 6)
        let solution = try solved(sketch)
        #expect(isClose(try #require(solution.points[sketch.ends(line).1]), Vector2(9, 12)))
        #expect(isClose(try #require(solution.radii[circle]), 4.5))
        let (_, arcStart, arcEnd) = sketch.arcPoints(arc)
        let solvedStart = try #require(solution.points[arcStart])
        #expect(isClose((solvedStart - Vector2(50, 0)).length, 6))
        #expect(isNear(solvedStart, Vector2(56, 0)))
        // The implicit equal-radius condition carries the end point too.
        #expect(isClose((try #require(solution.points[arcEnd]) - Vector2(50, 0)).length, 6))
    }

    @Test func angleBetweenLinesKeepsItsDrawnSense() throws {
        var sketch = Sketch()
        let reference = fixedLine(&sketch, .zero, Vector2(10, 0))
        let start = fixedPoint(&sketch, .zero)
        let up = sketch.addLine(from: start, to: sketch.addPoint(Vector2(10, 4)))
        let down = sketch.addLine(from: start, to: sketch.addPoint(Vector2(10, -4)))
        sketch.addDimension(.angle(reference, up), value: 30)
        sketch.addDimension(.angle(reference, down), value: 30)
        let solution = try solved(sketch)
        let upEnd = try #require(solution.points[sketch.ends(up).1])
        let downEnd = try #require(solution.points[sketch.ends(down).1])
        #expect(isClose(atan2(upEnd.y, upEnd.x) * 180 / .pi, 30))
        #expect(isClose(atan2(downEnd.y, downEnd.x) * 180 / .pi, -30))
    }

    @Test func referenceDimensionsMeasureWithoutDriving() throws {
        var sketch = Sketch()
        let line = sketch.addLine(from: fixedPoint(&sketch, .zero), to: fixedPoint(&sketch, Vector2(3, 4)))
        let measured = sketch.addDimension(.length(line), value: 99, isDriving: false)
        let solution = try solved(sketch)
        #expect(solution.status == .solved)
        #expect(isClose(try #require(solution.measurements[measured]), 5))
    }

    /// A driving angle is met by θ or 180° − θ, depending on which way each line runs. A
    /// reference angle on the same lines reads in that same sense, nearest its stored value.
    @Test func referenceAnglesAgreeWithDrivingAnglesOnLinesDrawnBackwards() throws {
        var sketch = Sketch()
        let reference = fixedLine(&sketch, .zero, Vector2(10, 0))
        let start = fixedPoint(&sketch, Vector2(20, 0))
        let backwards = Vector2(20 + 10 * cos(212 * Double.pi / 180), 10 * sin(212 * Double.pi / 180))
        let line = sketch.addLine(from: start, to: sketch.addPoint(backwards))
        sketch.addDimension(.angle(reference, line), value: 30)
        let measured = sketch.addDimension(.angle(reference, line), value: 30, isDriving: false)
        let supplementary = sketch.addDimension(.angle(reference, line), value: 140, isDriving: false)
        let solution = try solved(sketch)
        #expect(isClose(try #require(solution.measurements[measured]), 30))
        #expect(isClose(try #require(solution.measurements[supplementary]), 150))
    }
}
