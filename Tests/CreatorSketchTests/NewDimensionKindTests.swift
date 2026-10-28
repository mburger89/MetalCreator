import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// The centre, line-to-line, horizontal and vertical distance dimensions (DIM-2 spec §3).
struct NewDimensionKindTests {
    @Test func aHorizontalDistanceKeepsItsSide() throws {
        for (drawn, sign) in [(10.0, 1.0), (-10.0, -1.0)] {
            var sketch = Sketch()
            let a = sketch.addPoint(.zero)
            let b = sketch.addPoint(Vector2(drawn, 5))
            sketch.add(.fix(a, at: .zero))
            sketch.addDimension(.verticalDistance(a, b), value: 5)
            let horizontal = sketch.addDimension(.horizontalDistance(a, b), value: abs(drawn))
            for value in stride(from: 10.0, through: 0.5, by: -0.5) {
                sketch.dimensions[horizontal]?.value = value
                let solution = SketchSolver.solve(sketch)
                #expect(solution.status == .solved, "value \(value)")
                let point = try #require(solution.points[b])
                #expect(isClose(point, Vector2(sign * value, 5)), "value \(value), side \(sign)")
                sketch.remember(solution)
            }
        }
    }

    @Test func aVerticalDistanceReachesACircleCentre() throws {
        var sketch = Sketch()
        let a = sketch.addPoint(.zero)
        sketch.add(.fix(a, at: .zero))
        let circle = sketch.addCircle(center: Vector2(3, 12), radius: 4)
        sketch.addDimension(.horizontalDistance(a, circle), value: 3)
        sketch.addDimension(.verticalDistance(a, circle), value: 20)
        let solution = SketchSolver.solve(sketch)
        let centre = try #require(solution.points[sketch.centerOf(circle)])
        #expect(isClose(centre, Vector2(3, 20)))
        #expect(isClose(try #require(solution.radii[circle]), 4))
    }

    /// The circles' radii stay free, so the sketch is under-constrained but usable.
    @Test func aCentreDistanceSweepNeverCrossesOver() throws {
        var sketch = Sketch()
        let first = sketch.addCircle(center: .zero, radius: 5)
        let second = sketch.addCircle(center: Vector2(30, 0.4), radius: 3)
        sketch.add(.fix(sketch.centerOf(first), at: .zero))
        sketch.add(.horizontalPoints(sketch.centerOf(first), sketch.centerOf(second)))
        let distance = sketch.addDimension(.centreDistance(first, second), value: 30)
        let values = Array(stride(from: 30.0, through: 2, by: -1)) + Array(stride(from: 3.0, through: 60, by: 1))
        for value in values {
            sketch.dimensions[distance]?.value = value
            let solution = SketchSolver.solve(sketch)
            #expect(solution.status.isUsable, "value \(value)")
            let centre = try #require(solution.points[sketch.centerOf(second)])
            #expect(isClose(centre.x, value) && centre.x > 0, "value \(value)")
            sketch.remember(solution)
        }
    }

    @Test func aLineDistanceSweepKeepsTheTopAbove() throws {
        var sketch = Sketch()
        let bottom = sketch.addLine(.zero, Vector2(60, 0))
        let top = sketch.addLine(Vector2(0, 40), Vector2(60, 40.5))
        let (bottomStart, bottomEnd) = sketch.ends(bottom)
        let (topStart, topEnd) = sketch.ends(top)
        sketch.add(.fix(bottomStart, at: .zero))
        sketch.add(.fix(bottomEnd, at: Vector2(60, 0)))
        sketch.add(.horizontal(top))
        sketch.add(.verticalPoints(topStart, bottomStart))
        sketch.addDimension(.length(top), value: 60)
        let distance = sketch.addDimension(.lineDistance(bottom, top), value: 40)
        let values = Array(stride(from: 40.0, through: 1, by: -1)) + Array(stride(from: 2.0, through: 80, by: 1))
        for value in values {
            sketch.dimensions[distance]?.value = value
            let solution = SketchSolver.solve(sketch)
            #expect(solution.status == .solved, "value \(value)")
            for end in [topStart, topEnd] {
                let y = try #require(solution.points[end]).y
                #expect(isClose(y, value) && y > 0, "value \(value)")
            }
            sketch.remember(solution)
        }
    }

    @Test func aLineDistanceMeasuresAlongTheFirstNormal() throws {
        var sketch = Sketch()
        let first = sketch.addLine(.zero, Vector2(10, 0))
        let second = sketch.addLine(Vector2(0, 4), Vector2(10, 8))
        let forward = sketch.addDimension(.lineDistance(first, second), value: 1, isDriving: false)
        let swapped = sketch.addDimension(.lineDistance(second, first), value: 1, isDriving: false)
        let solution = SketchSolver.solve(sketch)
        #expect(isClose(try #require(solution.measurements[forward]), 6))
        #expect(isClose(try #require(solution.measurements[swapped]), 60 / 116.0.squareRoot()))
    }

    @Test func centreDistancesMeasureBetweenCentres() throws {
        var sketch = Sketch()
        let circle = sketch.addCircle(center: .zero, radius: 2)
        let centre = sketch.addPoint(Vector2(3, 4))
        let arc = sketch.addArc(center: centre, start: sketch.addPoint(Vector2(5, 4)), end: sketch.addPoint(Vector2(3, 6)))
        let point = sketch.addPoint(Vector2(6, 8))
        let toArc = sketch.addDimension(.centreDistance(circle, arc), value: 1, isDriving: false)
        let toPoint = sketch.addDimension(.centreDistance(circle, point), value: 1, isDriving: false)
        let solution = SketchSolver.solve(sketch)
        #expect(isClose(try #require(solution.measurements[toArc]), 5))
        #expect(isClose(try #require(solution.measurements[toPoint]), 10))
    }

    @Test func wrongGeometryIsRefusedInWords() {
        var sketch = Sketch()
        let p = sketch.addPoint(.zero)
        let q = sketch.addPoint(Vector2(5, 0))
        let line = sketch.addLine(Vector2(0, 3), Vector2(5, 3))
        let centre = sketch.addDimension(.centreDistance(p, q), value: 5)
        #expect(SketchSolver.solve(sketch).status
                == .failed(reason: "Centre Distance d1 (5 mm) needs two circles or arcs, or a circle or arc and a point."))
        sketch.dimensions[centre] = nil
        let lines = sketch.addDimension(.lineDistance(p, line), value: 5)
        #expect(SketchSolver.solve(sketch).status == .failed(reason: "Distance d2 (5 mm) needs two lines."))
        sketch.dimensions[lines] = nil
        sketch.addDimension(.horizontalDistance(line, p), value: 5)
        #expect(SketchSolver.solve(sketch).status
                == .failed(reason: "Horizontal Distance d3 (5 mm) needs two points, circles or arcs."))
    }

    @Test func aZeroHorizontalDistanceIsRefused() {
        var sketch = Sketch()
        let p = sketch.addPoint(.zero)
        let q = sketch.addPoint(Vector2(5, 0))
        sketch.addDimension(.horizontalDistance(p, q), value: 0)
        #expect(SketchSolver.solve(sketch).status
                == .failed(reason: "Horizontal Distance d1 must be greater than 0 mm, not 0 mm."))
    }

    @Test func theNewKindsTitleThemselves() {
        var sketch = Sketch()
        let ids = [DimensionKind.centreDistance(SketchEntityID(1), SketchEntityID(2)),
                   .lineDistance(SketchEntityID(1), SketchEntityID(2)),
                   .horizontalDistance(SketchEntityID(1), SketchEntityID(2)),
                   .verticalDistance(SketchEntityID(1), SketchEntityID(2)),
        ].map { sketch.addDimension($0, value: 5) }
        let titles = ids.compactMap { sketch.dimensions[$0].map { sketch.title(of: $0) } }
        #expect(titles == ["Centre Distance d1", "Distance d2", "Horizontal Distance d3", "Vertical Distance d4"])
    }

    @Test func theNewKindsAreLengths() {
        let (a, b) = (SketchEntityID(1), SketchEntityID(2))
        for kind in [DimensionKind.centreDistance(a, b), .lineDistance(a, b), .horizontalDistance(a, b), .verticalDistance(a, b)] {
            #expect(kind.quantity == .length)
            #expect(kind.entities == [a, b])
        }
    }

    @Test func aProjectedCircleGivesItsCentre() throws {
        var sketch = Sketch()
        let source = ProjectionSource(reference: "e", curve: .circle(center: Vector2(10, 0), radius: 2))
        let projected = sketch.add(SketchEntity(.projected(source)))
        let point = sketch.addPoint(Vector2(30, 1))
        sketch.addDimension(.centreDistance(projected, point), value: 25)
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status.isUsable)
        let position = try #require(solution.points[point])
        #expect(isClose((position - Vector2(10, 0)).length, 25))
    }
}
