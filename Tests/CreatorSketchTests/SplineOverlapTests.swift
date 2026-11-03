import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// Splines that overlap other curves merge like duplicate lines, fast; the exact containment and the nested self-crossing search.
struct SplineOverlapTests {

    // MARK: Overlaps merge like duplicate lines

    /// A square of side `side` from four points; returns the corner points.
    func square(_ sketch: inout Sketch, side: Double) -> [SketchEntityID] {
        let corners = [Vector2(0, 0), Vector2(side, 0), Vector2(side, side), Vector2(0, side)].map { sketch.addPoint($0) }
        for index in 0..<4 { _ = sketch.addLine(from: corners[index], to: corners[(index + 1) % 4]) }
        return corners
    }

    func summary(_ sketch: Sketch) -> (regions: Int, area: Double, segments: Int, seconds: Double) {
        let start = Date()
        let result = SketchRegions.find(in: sketch)
        let seconds = Date().timeIntervalSince(start)
        return (result.regions.count, result.regions.first?.area ?? 0, result.regions.first?.outer.count ?? 0, seconds)
    }

    @Test func aSplineOverASquaresEdgeMergesWithIt() {
        var sketch = Sketch()
        let corners = square(&sketch, side: 10)
        _ = sketch.addSpline(through: [corners[0], corners[1]])
        let result = summary(sketch)
        #expect(result.regions == 1 && result.segments == 4)
        #expect(isClose(result.area, 100, tolerance: 1e-6))
        #expect(result.seconds < 2, "\(result.seconds) s")
    }

    @Test func aCollinearThreePointSplineAlongAnEdgeMergesWithIt() {
        var sketch = Sketch()
        let corners = square(&sketch, side: 40)
        _ = sketch.addSpline(through: [corners[0], sketch.addPoint(Vector2(17, 0)), corners[1]])
        let result = summary(sketch)
        #expect(result.regions == 1 && result.segments == 4)
        #expect(isClose(result.area, 1600, tolerance: 1e-6))
        #expect(result.seconds < 2, "\(result.seconds) s")
    }

    @Test func aSplineRunningPastBothEndsOfAnEdgeMergesWithIt() {
        var sketch = Sketch()
        _ = square(&sketch, side: 10)
        _ = sketch.addSpline([Vector2(-5, 0), Vector2(15, 0)])
        let result = summary(sketch)
        #expect(result.regions == 1 && result.segments == 4)
        #expect(isClose(result.area, 100, tolerance: 1e-6))
        #expect(result.seconds < 2, "\(result.seconds) s")
    }

    @Test func twoSplinesThroughTheSamePointsMerge() {
        var sketch = Sketch()
        let a = sketch.addPoint(Vector2(0, 0))
        let b = sketch.addPoint(Vector2(5, 4))
        let c = sketch.addPoint(Vector2(10, 0))
        _ = sketch.addSpline(through: [a, b, c])
        _ = sketch.addSpline(through: [a, b, c])
        _ = sketch.addLine(from: c, to: a)
        let result = summary(sketch)
        #expect(result.regions == 1 && result.segments == 2)
        #expect(result.seconds < 2, "\(result.seconds) s")
    }

    @Test func aTriangleWithATwoPointSplineSideIsTheLineTriangle() throws {
        var lines = Sketch()
        let points = [Vector2(0, 0), Vector2(10, 0), Vector2(4, 7)].map { lines.addPoint($0) }
        for index in 0..<3 { _ = lines.addLine(from: points[index], to: points[(index + 1) % 3]) }
        var mixed = Sketch()
        let corners = [Vector2(0, 0), Vector2(10, 0), Vector2(4, 7)].map { mixed.addPoint($0) }
        _ = mixed.addSpline(through: [corners[0], corners[1]])
        _ = mixed.addLine(from: corners[1], to: corners[2])
        _ = mixed.addLine(from: corners[2], to: corners[0])
        let (expected, actual) = (summary(lines), summary(mixed))
        #expect(actual.regions == 1 && actual.segments == 3 && expected.segments == 3)
        #expect(isClose(actual.area, expected.area, tolerance: 1e-6))
    }

    @Test func aTightLoopInsideOneSpanIsASelfCrossing() {
        // Strong end tangents make the one span loop on itself well inside either half of it.
        let definition = SplineDefinition(points: [Vector2(0, 0), Vector2(1, 0)], handles: [
            SplineHandle(tangent: Vector2(30, -30)), SplineHandle(tangent: Vector2(30, 30))])
        let shape = CurveShape.spline(definition.curve())
        // The premise: a brute-force check of non-neighbouring chords of a dense sampling finds the loop.
        let dense = (0..<2000).map { shape.point(at: shape.parameterEnd * Double($0) / 1999) }
        func crosses(_ i: Int, _ j: Int) -> Bool {
            let (p, q, r, s) = (dense[i], dense[i + 1], dense[j], dense[j + 1])
            let (d1, d2) = (q - p, s - r)
            let denominator = SketchMath.cross(d1, d2)
            guard abs(denominator) > 1e-12 else { return false }
            let (t, u) = (SketchMath.cross(r - p, d2) / denominator, SketchMath.cross(r - p, d1) / denominator)
            return (0...1).contains(t) && (0...1).contains(u)
        }
        let loops = (0..<1990).contains { i in ((i + 5)..<1999).contains { crosses(i, $0) } }
        #expect(loops, "the fixture loops")
        let points = CurveIntersection.selfCrossings(of: shape)
        #expect(!points.isEmpty, "the loop is found")
    }

    @Test func splineContainmentIsExactBetweenThePolylineAndTheCurve() {
        let curve = SplineDefinition(points: [Vector2(0, 0), Vector2(20, 12), Vector2(40, 0)]).curve()
        let range = curve.parameterRange
        let samples = (0...20_000).map { curve.point(at: range.lowerBound + (range.upperBound - range.lowerBound) * Double($0) / 20_000) }
        let top = samples.max { $0.y < $1.y }!
        let loop = [
            LoopSegment(geometry: .spline(curve), source: 0, start: Vector2(0, 0), end: Vector2(40, 0)),
            LoopSegment(geometry: .line(Vector2(40, 0), Vector2(0, 0)), source: 1, start: Vector2(40, 0), end: Vector2(0, 0)),
        ]
        // Far closer to the curve than a 32-chord polyline's sag (millimetres here).
        #expect(LoopMeasure.contains(loop, Vector2(top.x, top.y - 1e-4)))
        #expect(!LoopMeasure.contains(loop, Vector2(top.x, top.y + 1e-4)))
        #expect(LoopMeasure.contains(loop, Vector2(20, 6)) && !LoopMeasure.contains(loop, Vector2(20, 13)))
    }
}
