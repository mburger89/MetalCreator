import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// Turning a sketch into equations: layout, warm start, branch choices and refusals (spec §4).
struct TermBuilderTests {
    func build(_ sketch: Sketch) throws(SolveFailure) -> TermBuilder.Output {
        let layout = UnknownLayout(sketch)
        return try TermBuilder(sketch: sketch, layout: layout, x0: layout.warmStart(sketch)).build()
    }

    func refusal(_ sketch: Sketch) -> String? {
        do {
            _ = try build(sketch)
            return nil
        } catch {
            return error.reason
        }
    }

    @Test func columnsFollowEntityIDsAndWarmStartPrefersTheLastSolve() {
        var sketch = Sketch()
        let a = sketch.addPoint(Vector2(1, 2))
        let circle = sketch.addCircle(center: a, radius: 3)
        let b = sketch.addPoint(Vector2(4, 5))
        sketch.solved[b] = .point(Vector2(6, 7))
        let layout = UnknownLayout(sketch)
        #expect(layout.pointColumns[a] == 0)
        #expect(layout.radiusColumns[circle] == 2)
        #expect(layout.pointColumns[b] == 3)
        #expect(layout.warmStart(sketch) == [1, 2, 3, 6, 7])
    }

    @Test func rowsThatHoldWhateverTheGeometryAreDropped() throws {
        var sketch = Sketch()
        let center = sketch.addPoint(.zero)
        let inner = sketch.addCircle(center: center, radius: 2)
        let outer = sketch.addCircle(center: center, radius: 3)
        let line = sketch.addLine(Vector2(5, 0), Vector2(9, 1))
        let flat = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(.zero, Vector2(10, 0))))))
        let tilted = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "f", curve: .line(.zero, Vector2(10, 3))))))
        sketch.add(.concentric(inner, outer))
        sketch.add(.coincident(center, center))
        sketch.add(.parallel(line, line))
        sketch.add(.equal(line, line))
        sketch.add(.horizontal(flat))
        sketch.addDimension(.angle(line, line), value: 0)
        // Constants that disagree are kept, so the solve can name them.
        let impossible = sketch.add(.horizontal(tilted))
        #expect(try build(sketch).terms.map(\.role) == [.user(.constraint(impossible))])
    }

    @Test func arcsAddTheImplicitRadiusTermAndReferenceDimensionsAddNothing() throws {
        var sketch = Sketch()
        let center = sketch.addPoint(.zero)
        let arc = sketch.addArc(center: center, start: sketch.addPoint(Vector2(5, 0)), end: sketch.addPoint(Vector2(0, 5)))
        sketch.addDimension(.radius(arc), value: 5, isDriving: false)
        let output = try build(sketch)
        #expect(output.terms.count == 1)
        #expect(output.terms.first?.role == .implicit)
    }

    @Test func lineOrientationsAreAngleBasedAndScaledByLength() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(8, 6))
        let horizontal = sketch.add(.horizontal(line))
        let term = try #require(try build(sketch).terms.first)
        #expect(term.role == .user(.constraint(horizontal)))
        // Length 10 at the warm start; the residual is 10 · (angle to x) = 10 · atan2(6, 8).
        #expect(term.equation == .horizontalLine(LineOperand(start: .unknown(column: 0), end: .unknown(column: 2)), scale: 10))
        #expect(isClose(term.equation.rows([0, 0, 8, 6])[0].value, 10 * atan2(6, 8), tolerance: 1e-12))
    }

    @Test func pointToLineDistanceKeepsTheDrawnSide() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let below = sketch.addPoint(Vector2(3, -2))
        sketch.addDimension(.distance(below, line), value: 5)
        let term = try #require(try build(sketch).terms.first)
        guard case .lineDistance(_, _, let value, let side) = term.equation else {
            Issue.record("not a line distance: \(term.equation)")
            return
        }
        #expect(value == 5)
        #expect(side == -1)
    }

    @Test func angleTargetTakesTheSignOfTheDrawnAngle() throws {
        var sketch = Sketch()
        let base = sketch.addLine(.zero, Vector2(10, 0))
        let down = sketch.addLine(.zero, Vector2(10, -6))
        sketch.addDimension(.angle(base, down), value: 30)
        let term = try #require(try build(sketch).terms.first)
        guard case .angle(_, _, let target, let scale) = term.equation else {
            Issue.record("not an angle: \(term.equation)")
            return
        }
        #expect(isClose(target, -.pi / 6, tolerance: 1e-12))
        #expect(isClose(scale, (10 + 136.0.squareRoot()) / 2, tolerance: 1e-12))
    }

    @Test func tangentAtASharedEndpointUsesThePerpendicularForm() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let (_, joint) = sketch.ends(line)
        let center = sketch.addPoint(Vector2(10, 5))
        let arc = sketch.addArc(center: center, start: joint, end: sketch.addPoint(Vector2(15, 5)))
        sketch.add(.tangent(line, arc))
        let circle = sketch.addCircle(center: Vector2(30, 5), radius: 5)
        sketch.add(.tangent(circle, line))
        let terms = try build(sketch).terms.filter { $0.role != .implicit }
        try #require(terms.count == 2)
        #expect(terms[0].equation == .tangentAtPoint(.unknown(column: 2), center: .unknown(column: 4),
                                                    LineOperand(start: .unknown(column: 0), end: .unknown(column: 2))))
        guard case .lineTangent(_, _, let side) = terms[1].equation else {
            Issue.record("not a line tangent: \(terms[1].equation)")
            return
        }
        #expect(side == 1)
    }

    @Test func circleTangencyIsInternalWhenDrawnInside() throws {
        var sketch = Sketch()
        let outer = sketch.addCircle(center: .zero, radius: 10)
        let inner = sketch.addCircle(center: Vector2(3, 0), radius: 6)
        sketch.add(.tangent(inner, outer))
        let term = try #require(try build(sketch).terms.first)
        guard case .circleTangent(_, _, let isInternal, let sign) = term.equation else {
            Issue.record("not a circle tangent: \(term.equation)")
            return
        }
        #expect(isInternal)
        #expect(sign == -1)
    }

    @Test func suspendedProjectionsAreSkipped() throws {
        var sketch = Sketch()
        let edge = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(.zero, Vector2(1, 0)),
                                                                     isSuspended: true))))
        let point = sketch.addPoint(.zero)
        let constraint = sketch.add(.pointOn(point: point, curve: edge))
        let dimension = sketch.addDimension(.distance(point, edge), value: 2)
        let output = try build(sketch)
        #expect(output.terms.isEmpty)
        #expect(output.suspended == [.constraint(constraint), .dimension(dimension)])
    }

    @Test func refusalsAreInPlainLanguage() {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let circle = sketch.addCircle(center: Vector2(20, 0), radius: 2)
        var negative = sketch
        negative.addDimension(.radius(circle), value: 0)
        #expect(refusal(negative) == "Radius d1 must be greater than 0 mm, not 0 mm.")
        var wrongKind = sketch
        wrongKind.add(.parallel(line, circle))
        #expect(refusal(wrongKind) == "Parallel on Line 1 and Circle 1 needs two lines.")
        var badRadius = sketch
        let center = badRadius.centerOf(circle)
        badRadius.entities[circle]?.kind = .circle(center: center, radius: -1)
        #expect(refusal(badRadius) == "Circle 1 needs a radius greater than 0 mm.")
        var sharedPoints = sketch
        let (start, _) = sharedPoints.ends(line)
        sharedPoints.entities[line]?.kind = .line(start: start, end: start)
        #expect(refusal(sharedPoints) == "Line 1 starts and ends at the same point.")
        #expect(refusal(sketch) == nil)
    }

    @Test func aConstraintOnAMissingEntityIsRefusedNotSolvedAround() {
        // An edited or damaged file: the constraint outlived its point.
        var sketch = Sketch()
        let point = sketch.addPoint(.zero)
        sketch.add(.coincident(point, SketchEntityID(99)))
        #expect(refusal(sketch) == "Coincident on Point 1 and a deleted entity refers to geometry that no longer exists.")
    }

    @Test func aWiredValueThatIsNotANumberIsRefused() {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let length = sketch.addDimension(.length(line), value: 10)
        for bad in [Double.nan, .infinity, -.infinity] {
            sketch.dimensions[length]?.value = bad
            #expect(refusal(sketch) == "Length d1 is not a number.")
        }
    }
}
