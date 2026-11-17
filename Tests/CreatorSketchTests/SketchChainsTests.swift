import CreatorGeometry
import Testing
@testable import CreatorSketch

/// The Sketch node's curves: every non-construction curve chained at points where exactly two ends meet.
struct SketchChainsTests {
    @Test func aRectangleIsOneClosedChainOfFour() {
        var sketch = Sketch()
        let lines = addPolygon(&sketch, [Vector2(0, 0), Vector2(10, 0), Vector2(10, 5), Vector2(0, 5)])
        let chains = SketchChains.find(in: sketch)
        #expect(chains.count == 1)
        #expect(chains[0].isClosed && chains[0].segments.count == 4)
        #expect(chains[0].sources == lines)
        for (a, b) in zip(chains[0].segments, chains[0].segments.dropFirst() + [chains[0].segments[0]]) {
            #expect(isClose(a.endPoint, b.startPoint))
        }
    }

    @Test func aTJunctionGivesThreeOpenChains() {
        var sketch = Sketch()
        let middle = sketch.addPoint(Vector2(0, 0))
        for end in [Vector2(10, 0), Vector2(-5, 5), Vector2(-5, -5)] {
            _ = sketch.addLine(from: middle, to: sketch.addPoint(end))
        }
        let chains = SketchChains.find(in: sketch)
        #expect(chains.count == 3)
        #expect(chains.allSatisfy { !$0.isClosed && $0.segments.count == 1 })
    }

    @Test func anOpenPolylineWithAnArcIsOneChainInOrder() {
        var sketch = Sketch()
        let points = [Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)].map { sketch.addPoint($0) }
        let first = sketch.addLine(from: points[0], to: points[1])
        let second = sketch.addLine(from: points[1], to: points[2])
        let center = sketch.addPoint(Vector2(10, 15))
        let arcEnd = sketch.addPoint(Vector2(15, 15))
        // The arc runs counter-clockwise from (10, 10) to (15, 15) about (10, 15)... its start is the line's end.
        let arc = sketch.addArc(center: center, start: points[2], end: arcEnd)
        let third = sketch.addLine(from: arcEnd, to: sketch.addPoint(Vector2(30, 15)))
        let chains = SketchChains.find(in: sketch)
        #expect(chains.count == 1 && !chains[0].isClosed)
        #expect(chains[0].sources == [first, second, arc, third])
        for (a, b) in zip(chains[0].segments, chains[0].segments.dropFirst()) {
            #expect(isClose(a.endPoint, b.startPoint, tolerance: 1e-6))
        }
    }

    @Test func aChainWalksTowardTheFarEndWhenTheLowerCurveIsReversed() {
        var sketch = Sketch()
        let a = sketch.addPoint(Vector2(0, 0)), b = sketch.addPoint(Vector2(5, 0)), c = sketch.addPoint(Vector2(10, 0))
        _ = sketch.addLine(from: b, to: a)
        _ = sketch.addLine(from: b, to: c)
        let chains = SketchChains.find(in: sketch)
        #expect(chains.count == 1)
        #expect(isClose(chains[0].segments[0].endPoint, chains[0].segments[1].startPoint))
    }

    @Test func aConstructionLineGivesNothing() {
        var sketch = Sketch()
        _ = sketch.addLine(Vector2(0, 0), Vector2(5, 5), isConstruction: true)
        #expect(SketchChains.find(in: sketch).isEmpty)
    }

    @Test func aCircleAndASeparateSplineAreTwoChains() {
        var sketch = Sketch()
        let circle = sketch.addCircle(center: Vector2(0, 0), radius: 3)
        let spline = sketch.addSpline([Vector2(10, 0), Vector2(12, 4), Vector2(15, 5)])
        let chains = SketchChains.find(in: sketch)
        #expect(chains.count == 2)
        #expect(chains[0].isClosed && chains[0].sources == [circle])
        #expect(!chains[1].isClosed && chains[1].sources == [spline])
    }
}
