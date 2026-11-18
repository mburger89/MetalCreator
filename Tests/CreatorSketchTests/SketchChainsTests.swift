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

    @Test func anArcAndASplineWalkedBackwardsAreReversed() throws {
        var sketch = Sketch()
        let a = sketch.addPoint(Vector2(0, 0)), b = sketch.addPoint(Vector2(10, 0))
        let c = sketch.addPoint(Vector2(10, 10)), d = sketch.addPoint(Vector2(20, 10))
        _ = sketch.addLine(from: a, to: b)
        let center = sketch.addPoint(Vector2(10, 5))
        // Counter-clockwise from c to b about (10, 5), so the chain from a reaches it at its end.
        _ = sketch.addArc(center: center, start: c, end: b)
        _ = sketch.addSpline(through: [d, sketch.addPoint(Vector2(15, 14)), c])
        let chain = try #require(SketchChains.find(in: sketch).first)
        #expect(chain.segments.count == 3 && !chain.isClosed)
        guard case .arc(_, _, let start, let end) = chain.segments[1] else { Issue.record("not an arc"); return }
        #expect(end.radians < start.radians)
        for (x, y) in zip(chain.segments, chain.segments.dropFirst()) { #expect(isClose(x.endPoint, y.startPoint, tolerance: 1e-6)) }
        #expect(isClose(chain.segments[2].endPoint, Vector2(20, 10), tolerance: 1e-6))
    }

    @Test func aClosedCycleWhoseFirstCurveIsStoredReversedStillClosesInOrder() {
        var sketch = Sketch()
        let p = [Vector2(0, 0), Vector2(10, 0), Vector2(5, 8), Vector2(-2, 5)].map { sketch.addPoint($0) }
        let lines = [sketch.addLine(from: p[1], to: p[0]), sketch.addLine(from: p[1], to: p[2]),
                     sketch.addLine(from: p[2], to: p[3]), sketch.addLine(from: p[3], to: p[0]),
        ]
        let chains = SketchChains.find(in: sketch)
        #expect(chains.count == 1 && chains[0].isClosed && chains[0].segments.count == 4)
        #expect(chains[0].sources == [lines[0], lines[3], lines[2], lines[1]])
        let segments = chains[0].segments
        for (x, y) in zip(segments, segments.dropFirst() + [segments[0]]) { #expect(isClose(x.endPoint, y.startPoint)) }
    }

    @Test func anUnrelatedEditElsewhereKeepsTheChainsOrder() {
        var sketch = Sketch()
        let circle = sketch.addCircle(center: Vector2(0, 0), radius: 3)
        let line = sketch.addLine(Vector2(10, 0), Vector2(20, 0))
        let before = SketchChains.find(in: sketch)
        _ = sketch.addLine(Vector2(50, 50), Vector2(60, 60))
        let after = SketchChains.find(in: sketch)
        #expect(after.count == 3)
        #expect(Array(after.prefix(2)) == before)
        #expect(after.map { $0.sources[0] }.prefix(2) == [circle, line])
    }
}
