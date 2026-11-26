import CreatorGeometry
import CreatorKernel
import Foundation
import Testing

@testable import CreatorDrawing

@Suite("Dimension measuring")
struct DrawingMeasureTests {
    private let front = StandardOrientation.front.frame

    private func v(_ x: Double, _ y: Double, _ z: Double) -> Vector3 { Vector3(x, y, z) }

    private func held(_ geometry: AnchorGeometry) -> AnchorResolution { .held(geometry, edges: [], isRun: false) }

    private func segment(_ a: Vector3, _ b: Vector3) -> AnchorResolution { held(.segment(a, b)) }

    private func point(_ p: Vector3) -> AnchorResolution { held(.point(p)) }

    private func measure(
        _ kind: DrawingDimensionKind, _ anchors: [AnchorResolution], angle: Double = 0, offset: Double = 5,
        frame: ProjectionFrame? = nil, mapping: ViewMapping? = nil
    ) -> Result<DrawingMeasurement, LostReason> {
        let dimension = DrawingDimension(kind: kind, anchors: [], placement: DimensionPlacement(offset: offset, angle: angle))
        return DrawingMeasure.measure(dimension, anchors: anchors, frame: frame ?? self.front, mapping: mapping)
    }

    private func expectValues(
        _ result: Result<DrawingMeasurement, LostReason>, _ values: [Double], sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard case .success(let measurement) = result else {
            Issue.record("expected a measurement, got \(result)", sourceLocation: sourceLocation)
            return
        }
        #expect(measurement.values.count == values.count, sourceLocation: sourceLocation)
        for (a, b) in zip(measurement.values, values) { #expect(abs(a - b) < 1e-9, sourceLocation: sourceLocation) }
    }

    private func figure(_ result: Result<DrawingMeasurement, LostReason>) -> AnnotationFigure? {
        if case .success(let measurement) = result { return measurement.figure }
        return nil
    }

    @Test func aHorizontalEdge() {
        let result = measure(.linear(.horizontal), [segment(v(0, 0, 0), v(40, 0, 0))])
        expectValues(result, [40])
        #expect(figure(result) == .linear(points: [Vector2(0, 0), Vector2(40, 0)], direction: Vector2(1, 0)))
    }

    @Test func aTiltedEdgeIsForeshortened() {
        let result = measure(.linear(.horizontal), [segment(v(0, 0, 0), v(40, 10, 0))])
        #expect(result == .failure(.foreshortened))
    }

    @Test func aVerticalBetweenCorners() {
        let result = measure(.linear(.vertical), [point(v(0, 0, 0)), point(v(0, 0, 25))])
        expectValues(result, [25])
        #expect(figure(result) == .linear(points: [Vector2(0, 0), Vector2(0, 25)], direction: Vector2(0, 1)))
    }

    @Test func aLineContributesItsEndNearerTheDimensionLine() {
        let line = segment(v(30, 0, 0), v(30, 0, 20))
        let above = measure(.linear(.horizontal), [point(v(0, 0, 0)), line], offset: 5)
        #expect(figure(above) == .linear(points: [Vector2(0, 0), Vector2(30, 20)], direction: Vector2(1, 0)))
        let below = measure(.linear(.horizontal), [point(v(0, 0, 0)), line], offset: -5)
        #expect(figure(below) == .linear(points: [Vector2(0, 0), Vector2(30, 0)], direction: Vector2(1, 0)))
    }

    @Test func alignedBetweenPoints() {
        let result = measure(.linear(.aligned), [point(v(0, 0, 0)), point(v(3, 0, 4))])
        expectValues(result, [5])
        guard case .linear(let points, let direction)? = figure(result) else {
            Issue.record("expected a linear figure")
            return
        }
        #expect(points == [Vector2(0, 0), Vector2(3, 4)])
        #expect(abs(direction.x - 0.6) < 1e-12 && abs(direction.y - 0.8) < 1e-12)
    }

    @Test func alignedBetweenPointsDeepInTheViewIsForeshortened() {
        #expect(measure(.linear(.aligned), [point(v(0, 0, 0)), point(v(3, 4, 4))]) == .failure(.foreshortened))
    }

    @Test func pointToLine() {
        let result = measure(.linear(.aligned), [point(v(0, 0, 5)), segment(v(-10, 0, 0), v(10, 0, 0))])
        expectValues(result, [5])
        #expect(figure(result) == .linear(points: [Vector2(0, 5), Vector2(0, 0)], direction: Vector2(0, -1)))
    }

    @Test func parallelLines() {
        let result = measure(.linear(.aligned), [segment(v(0, 0, 0), v(10, 0, 0)), segment(v(2, 0, 7), v(12, 0, 7))])
        expectValues(result, [7])
        #expect(figure(result) == .linear(points: [Vector2(0, 0), Vector2(0, 7)], direction: Vector2(0, 1)))
    }

    @Test func aDiameterOfAFaceOnCircle() {
        let circle = held(.circle(center: v(5, 6, 0), axis: v(0, 0, 1), radius: 3, sweep: 2 * .pi))
        let result = measure(.diameter, [circle], frame: StandardOrientation.top.frame)
        expectValues(result, [6])
        #expect(figure(result) == .radial(center: Vector2(5, 6), radius: 3, isDiameter: true))
        expectValues(measure(.radius, [circle], frame: StandardOrientation.top.frame), [3])
    }

    @Test func aCircleAnchorOfALinearDimensionMustBeFaceOn() {
        let tilted = held(.circle(center: v(5, 0, 6), axis: v(0, 0.2, 1).normalized ?? v(0, 0, 1), radius: 3, sweep: 2 * .pi))
        let faceOn = held(.circle(center: v(5, 0, 6), axis: v(0, 1, 0), radius: 3, sweep: 2 * .pi))
        #expect(measure(.linear(.horizontal), [tilted, point(v(0, 0, 0))]) == .failure(.foreshortened))
        #expect(measure(.linear(.aligned), [tilted, point(v(0, 0, 6))]) == .failure(.foreshortened))
        #expect(measure(.linear(.aligned), [point(v(0, 0, 6)), tilted]) == .failure(.foreshortened))
        expectValues(measure(.linear(.horizontal), [faceOn, point(v(0, 0, 0))]), [5])
    }

    @Test func aCircleSeenEdgeOnIsForeshortened() {
        let circle = held(.circle(center: v(5, 6, 0), axis: v(0, 0, 1), radius: 3, sweep: 2 * .pi))
        #expect(measure(.diameter, [circle]) == .failure(.foreshortened))
    }

    @Test func aSideOnCylinderDiameter() {
        let axis = held(.cylinder(axisPoint: v(0, 0, 0), axis: v(1, 0, 0), radius: 4, side: 0))
        let result = measure(.diameter, [axis])
        expectValues(result, [8])
        #expect(figure(result) == .linear(points: [Vector2(0, -4), Vector2(0, 4)], direction: Vector2(0, 1)))
        let end = held(.cylinder(axisPoint: v(0, 0, 0), axis: v(0, 1, 0), radius: 4, side: 0))
        #expect(measure(.diameter, [end]) == .failure(.foreshortened))
    }

    @Test func angleBySector() {
        let thirty = Double.pi / 6
        let lines = [segment(v(0, 0, 0), v(10, 0, 0)), segment(v(0, 0, 0), v(10 * cos(thirty), 0, 10 * sin(thirty)))]
        let near = measure(.angle, lines, angle: 15 * .pi / 180)
        expectValues(near, [thirty])
        #expect(
            figure(near)
                == .angle(
                    vertex: Vector2(0, 0), first: [Vector2(0, 0), Vector2(10, 0)],
                    second: [Vector2(0, 0), Vector2(10 * cos(thirty), 10 * sin(thirty))]))
        expectValues(measure(.angle, lines, angle: 105 * .pi / 180), [150 * .pi / 180])
        expectValues(measure(.angle, lines, angle: -75 * .pi / 180), [150 * .pi / 180])
    }

    @Test func aBaselineOrChainNeedsThreeAnchors() {
        let two = [point(v(0, 0, 0)), point(v(10, 0, 0))]
        #expect(measure(.baseline(.horizontal), two) == .failure(.notLineOrCircle))
        #expect(measure(.chain(.horizontal), two) == .failure(.notLineOrCircle))
    }

    @Test func anOutlineAnchorTakesItsSideFromTheSign() {
        let origin = point(v(0, 0, 0))
        func third(_ side: Double) -> Vector2? {
            let outline = held(.cylinder(axisPoint: v(0, 0, 0), axis: v(1, 0, 0), radius: 4, side: side))
            guard case .success(let measured) = measure(.linear(.vertical), [origin, outline]),
                case .linear(let points, _) = measured.figure else { return nil }
            return points[1]
        }
        let (above, below) = (third(1), third(-1))
        #expect(above != nil && below != nil)
        #expect(abs(abs(above?.y ?? 0) - 4) < 1e-9 && abs(abs(below?.y ?? 0) - 4) < 1e-9)
        #expect(abs((above?.y ?? 0) + (below?.y ?? 0)) < 1e-9, "the two sides lie opposite each other")
        #expect((above?.y ?? 0) != (below?.y ?? 0))
    }

    @Test func anAngleExtendsItsLinesToTheVertex() {
        // The lines meet at the origin, beyond both segments; the sector the placement points into decides the angle.
        let lines = [segment(v(2, 0, 0), v(10, 0, 0)), segment(v(2, 0, 2), v(6, 0, 6))]
        let inside = measure(.angle, lines, angle: 22.5 * .pi / 180)
        expectValues(inside, [.pi / 4])
        #expect(
            figure(inside)
                == .angle(vertex: Vector2(0, 0), first: [Vector2(2, 0), Vector2(10, 0)], second: [Vector2(2, 2), Vector2(6, 6)]))
        // Beyond the second line the supplementary sector (the other side of the vertex's four rays).
        expectValues(measure(.angle, lines, angle: 112.5 * .pi / 180), [3 * .pi / 4])
        expectValues(measure(.angle, lines, angle: 202.5 * .pi / 180), [.pi / 4])
        expectValues(measure(.angle, lines, angle: -45 * .pi / 180), [3 * .pi / 4])
    }

    @Test func baselineValues() {
        let points = [point(v(0, 0, 0)), point(v(10, 0, 0)), point(v(25, 0, 0))]
        let result = measure(.baseline(.horizontal), points)
        expectValues(result, [10, 25])
        #expect(figure(result) == .linear(points: [Vector2(0, 0), Vector2(10, 0), Vector2(25, 0)], direction: Vector2(1, 0)))
    }

    @Test func chainValues() {
        let points = [point(v(0, 0, 0)), point(v(10, 0, 0)), point(v(25, 0, 0))]
        expectValues(measure(.chain(.horizontal), points), [10, 15])
    }

    @Test func ordinateValues() {
        let points = [point(v(5, 0, 0)), point(v(10, 0, 3)), point(v(25, 0, 9))]
        let result = measure(.ordinate(.horizontal), points)
        expectValues(result, [5, 20])
        #expect(
            figure(result) == .ordinate(origin: Vector2(5, 0), points: [Vector2(10, 3), Vector2(25, 9)], direction: Vector2(1, 0)))
        expectValues(measure(.ordinate(.vertical), points), [3, 9])
    }

    @Test func chamferLeg() {
        let chamfer = segment(v(0, 0, 0), v(2, 0, 2))
        let result = measure(.chamfer, [chamfer, segment(v(0, 0, 0), v(10, 0, 0))])
        expectValues(result, [2, .pi / 4])
        #expect(figure(result) == .chamfer(start: Vector2(0, 0), end: Vector2(2, 2)))
    }

    @Test func anyLostAnchorLosesTheWhole() {
        let points = [point(v(0, 0, 0)), .lost(.missing), point(v(25, 0, 0))]
        #expect(measure(.baseline(.horizontal), points) == .failure(.missing))
        #expect(measure(.linear(.horizontal), [.lost(.cornerGone)]) == .failure(.cornerGone))
    }

    @Test func anEdgeWithNoCurveIsNotMeasured() {
        #expect(measure(.linear(.horizontal), [held(.other(midpoint: v(0, 0, 0)))]) == .failure(.notLineOrCircle))
    }

    @Test func theMappingMovesNothingInTheModelPlane() {
        let mapping = ViewMapping(scale: 0.5, offset: Vector2(100, 50))
        let result = measure(.linear(.horizontal), [segment(v(0, 0, 0), v(40, 0, 0))], mapping: mapping)
        expectValues(result, [40])
        #expect(mapping.sheet(Vector2(10, 20)) == Vector2(105, 60))
        #expect(mapping.model(Vector2(105, 60)) == Vector2(10, 20))
    }
}
