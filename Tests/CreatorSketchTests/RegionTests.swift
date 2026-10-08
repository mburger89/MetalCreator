import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// Region finding (spec §5, §10). Areas and centroids are analytic.
struct RegionTests {
    func square(_ sketch: inout Sketch, x: Double = 0, y: Double = 0, side: Double, isConstruction: Bool = false) {
        addPolygon(&sketch, [Vector2(x, y), Vector2(x + side, y), Vector2(x + side, y + side), Vector2(x, y + side)],
                   isConstruction: isConstruction)
    }

    @Test func squareWithACircularHoleIsOneRegionWithOneHole() throws {
        var sketch = Sketch()
        square(&sketch, side: 10)
        sketch.addCircle(center: Vector2(5, 5), radius: 2)
        let result = SketchRegions.find(in: sketch)
        #expect(result.regions.count == 1)
        let region = try #require(result.regions.first)
        #expect(region.outer.count == 4)
        #expect(region.holes.count == 1)
        #expect(isClose(region.area, 100 - 4 * .pi))
        #expect(isClose(region.centroid, Vector2(5, 5)))
        // The hole is the whole circle in one arc, emitted counter-clockwise like every loop.
        let hole = try #require(region.holes.first)
        #expect(hole.count == 1)
        guard case .arc(let center, let radius, let start, let end) = hole[0] else { Issue.record("hole is not an arc"); return }
        #expect(isClose(center, Vector2(5, 5)))
        #expect(radius == 2)
        #expect(isClose(end.radians - start.radians, 2 * .pi))
        #expect(result.warning == nil)
    }

    @Test func anIslandInsideAHoleIsASecondRegion() throws {
        var sketch = Sketch()
        square(&sketch, side: 20)
        sketch.addCircle(center: Vector2(10, 10), radius: 6)
        square(&sketch, x: 8, y: 8, side: 4)
        let regions = SketchRegions.find(in: sketch).regions
        try #require(regions.count == 2)
        #expect(isClose(regions[0].area, 400 - 36 * .pi))
        #expect(regions[0].holes.count == 1)
        #expect(isClose(regions[1].area, 16))
        #expect(regions[1].holes.isEmpty)
    }

    @Test func overlappingSquaresSplitIntoThreeRegions() throws {
        var sketch = Sketch()
        square(&sketch, side: 10)
        square(&sketch, x: 5, y: 5, side: 10)
        let regions = SketchRegions.find(in: sketch).regions
        try #require(regions.map(\.area).map { ($0 * 1e6).rounded() / 1e6 } == [75, 75, 25])
        // Equal areas order by centroid x: the lower-left L first.
        #expect(isClose(regions[0].centroid, Vector2(312.5 / 75, 312.5 / 75)))
        #expect(isClose(regions[1].centroid, Vector2(812.5 / 75, 812.5 / 75)))
        #expect(isClose(regions[2].centroid, Vector2(7.5, 7.5)))
    }

    @Test func squaresSharingPartOfAnEdgeGiveTwoRegions() throws {
        var sketch = Sketch()
        square(&sketch, side: 10)
        addPolygon(&sketch, [Vector2(10, 0), Vector2(20, 0), Vector2(20, 5), Vector2(10, 5)])
        let result = SketchRegions.find(in: sketch)
        let regions = result.regions
        try #require(regions.count == 2)
        #expect(isClose(regions[0].area, 100))
        #expect(isClose(regions[1].area, 50))
        #expect(result.openCurves.isEmpty)
        #expect(result.warning == nil)
    }

    @Test func aLineDrawnOverASquaresEdgeIsNotOpen() {
        var sketch = Sketch()
        square(&sketch, side: 10)
        sketch.addLine(Vector2(0, 0), Vector2(10, 0))
        let result = SketchRegions.find(in: sketch)
        #expect(result.regions.count == 1)
        #expect(result.openCurves.isEmpty)
        #expect(result.warning == nil)
    }

    @Test func aLineAcrossASquareSplitsItInTwo() {
        var sketch = Sketch()
        square(&sketch, side: 10)
        sketch.addLine(Vector2(-5, 4), Vector2(15, 4))
        let result = SketchRegions.find(in: sketch)
        #expect(result.regions.map(\.area).map { ($0 * 1e6).rounded() / 1e6 } == [60, 40])
        // The overhanging ends are dangling, but the line still bounds regions.
        #expect(result.openCurves.isEmpty)
    }

    @Test func externallyTangentCirclesAreTwoRegions() throws {
        var sketch = Sketch()
        sketch.addCircle(center: .zero, radius: 3)
        sketch.addCircle(center: Vector2(5, 0), radius: 2)
        let regions = SketchRegions.find(in: sketch).regions
        try #require(regions.count == 2)
        #expect(isClose(regions[0].area, 9 * .pi))
        #expect(isClose(regions[1].area, 4 * .pi))
    }

    @Test func internallyTangentCirclesAreACrescentAndADisk() throws {
        var sketch = Sketch()
        sketch.addCircle(center: .zero, radius: 4)
        sketch.addCircle(center: Vector2(2, 0), radius: 2)
        let regions = SketchRegions.find(in: sketch).regions
        try #require(regions.count == 2)
        #expect(isClose(regions[0].area, 12 * .pi))
        #expect(isClose(regions[1].area, 4 * .pi))
        #expect(regions.allSatisfy { $0.holes.isEmpty })
    }

    @Test func constructionGeometryIsIgnored() throws {
        var sketch = Sketch()
        square(&sketch, side: 50, isConstruction: true)
        sketch.addCircle(center: Vector2(25, 25), radius: 5)
        let result = SketchRegions.find(in: sketch)
        try #require(result.regions.count == 1)
        #expect(isClose(result.regions[0].area, 25 * .pi))
        #expect(result.openCurves.isEmpty)
    }

    @Test func openCurvesProduceAWarning() {
        var sketch = Sketch()
        square(&sketch, side: 10)
        let spur = sketch.addLine(Vector2(10, 5), Vector2(20, 5))
        let loose = sketch.addLine(Vector2(30, 0), Vector2(40, 3))
        let result = SketchRegions.find(in: sketch)
        #expect(result.regions.count == 1)
        #expect(result.openCurves == [spur, loose])
        #expect(result.warning == "2 curves don't form a closed region.")
    }

    @Test func projectedEdgesBoundRegions() throws {
        var sketch = Sketch()
        sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .circle(center: .zero, radius: 10)))))
        sketch.add(SketchEntity(.projected(ProjectionSource(reference: "f", curve: .circle(center: .zero, radius: 1),
                                                            isSuspended: true))))
        let regions = SketchRegions.find(in: sketch).regions
        try #require(regions.count == 1)
        #expect(isClose(regions[0].area, 100 * .pi))
    }

    @Test func slotAreaIncludesItsCaps() throws {
        let slot = ClassicSketchTests.Slot(length: 40, radius: 5)
        var sketch = slot.sketch
        sketch.remember(SketchSolver.solve(sketch))
        let region = try #require(SketchRegions.find(in: sketch).regions.first)
        #expect(region.outer.count == 4)
        #expect(isClose(region.area, 2 * 5 * 40 + 25 * .pi, tolerance: 1e-6))
    }

    @Test func notchedPlateKeepsAContinuousLoopThroughItsClockwiseArc() throws {
        // A plate with a semicircular notch in its top edge.
        var sketch = Sketch()
        let corners = [Vector2(0, 0), Vector2(20, 0), Vector2(20, 10), Vector2(14, 10), Vector2(6, 10), Vector2(0, 10)]
        let points = corners.map { sketch.addPoint($0) }
        for (a, b) in [(0, 1), (1, 2), (2, 3), (4, 5), (5, 0)] { sketch.addLine(from: points[a], to: points[b]) }
        let center = sketch.addPoint(Vector2(10, 10))
        sketch.addArc(center: center, start: points[4], end: points[3])
        let region = try #require(SketchRegions.find(in: sketch).regions.first)
        #expect(isClose(region.area, 200 - 8 * .pi))
        let profile = region.profile(on: .xy)
        #expect(profile.isClosed)
        let arcs = profile.segments.compactMap { segment -> Double? in
            if case .arc(_, _, let start, let end) = segment { return end.radians - start.radians }
            return nil
        }
        #expect(arcs.count == 1)
        #expect(isClose(arcs[0], -.pi))
    }

    @Test func regionOrderDoesNotDependOnDrawingOrder() throws {
        func circles(_ order: [Double]) -> [Vector2] {
            var sketch = Sketch()
            for x in order { sketch.addCircle(center: Vector2(x, 0), radius: 1) }
            return SketchRegions.find(in: sketch).regions.map(\.centroid)
        }
        let expected = [Vector2(-10, 0), Vector2(0, 0), Vector2(10, 0)]
        for order in [[0.0, 10, -10], [10.0, -10, 0], [-10.0, 0, 10]] {
            let centroids = circles(order)
            try #require(centroids.count == 3)
            #expect(zip(centroids, expected).allSatisfy { isClose($0, $1) })
        }
    }

    @Test func profileConversionCarriesTheHoles() throws {
        var sketch = Sketch()
        square(&sketch, side: 10)
        sketch.addCircle(center: Vector2(5, 5), radius: 2)
        let region = try #require(SketchRegions.find(in: sketch).regions.first)
        let profile = region.profile(on: .xz)
        #expect(profile.plane == .xz)
        #expect(profile.outer == region.outer)
        #expect(profile.holes == region.holes)
        #expect(profile.holes.count == 1)
        #expect(profile.isClosed)
    }

    /// Spec §5 step 5: holes sort by area descending, then centroid x, then y, whatever order
    /// they were drawn in, so a hole's loop index names the same wall after every edit.
    @Test func holesAreSortedByAreaThenCentroid() throws {
        let centres = [Vector2(30, 10), Vector2(10, 30), Vector2(10, 10), Vector2(30, 30)]
        let radii = [2.0, 3, 2, 2]
        let expected = [Vector2(10, 30), Vector2(10, 10), Vector2(30, 10), Vector2(30, 30)]
        for order in [[0, 1, 2, 3], [3, 2, 1, 0], [2, 0, 3, 1]] {
            var sketch = Sketch()
            square(&sketch, side: 40)
            for i in order { sketch.addCircle(center: centres[i], radius: radii[i]) }
            let region = try #require(SketchRegions.find(in: sketch).regions.first)
            let holeCentres = region.holes.compactMap { hole -> Vector2? in
                if case .arc(let center, _, _, _)? = hole.first { return center }
                return nil
            }
            #expect(holeCentres == expected, "order \(order)")
        }
    }

    /// Spec §5 step 5: every loop, holes included, runs counter-clockwise and starts at its
    /// lexicographically smallest start point, wherever the drawing started.
    @Test func everyLoopIsCounterClockwiseFromItsSmallestPoint() throws {
        var sketch = Sketch()
        // Outline drawn clockwise from its top-right corner; square hole drawn from its top-left.
        addPolygon(&sketch, [Vector2(20, 20), Vector2(20, 0), Vector2(0, 0), Vector2(0, 20)])
        addPolygon(&sketch, [Vector2(5, 15), Vector2(15, 15), Vector2(15, 5), Vector2(5, 5)])
        let region = try #require(SketchRegions.find(in: sketch).regions.first)
        try #require(region.holes.count == 1)
        for (loop, smallest) in [(region.outer, Vector2(0, 0)), (region.holes[0], Vector2(5, 5))] {
            #expect(isClose(try #require(loop.first).startPoint, smallest))
            #expect(signedArea(loop) > 0)
        }
        #expect(region.profile(on: .xy).isClosed)
    }

    /// The shoelace area of a line-only loop.
    func signedArea(_ loop: [Segment2D]) -> Double {
        loop.reduce(0) { total, segment in
            let (p, q) = (segment.startPoint, segment.endPoint)
            return total + 0.5 * (p.x * q.y - q.x * p.y)
        }
    }

    @Test func cornersJoinedByCoincidentConstraintsCloseARegionOnceSolved() throws {
        // Lines drawn with gaps and joined only by coincident constraints, as an editor that
        // doesn't share points would leave them.
        var sketch = Sketch()
        let corners = [Vector2(0, 0), Vector2(30, 0), Vector2(18, 20)]
        let lines = (0..<3).map { i in
            let gap = Vector2(0.3 * Double(i + 1), -0.4 * Double(i))
            return sketch.addLine(corners[i] + gap, corners[(i + 1) % 3] - gap)
        }
        for i in 0..<3 { sketch.add(.coincident(sketch.ends(lines[i]).1, sketch.ends(lines[(i + 1) % 3]).0)) }
        sketch.add(.fix(sketch.ends(lines[0]).0, at: .zero))
        for (line, value) in zip(lines, [31.7, 24.3, 25]) { sketch.addDimension(.length(line), value: value) }
        #expect(SketchRegions.find(in: sketch).regions.isEmpty)
        sketch.remember(SketchSolver.solve(sketch))
        let result = SketchRegions.find(in: sketch)
        try #require(result.regions.count == 1)
        #expect(result.warning == nil)
        // Heron's formula for sides 31.7, 24.3, 25.
        let s = (31.7 + 24.3 + 25) / 2
        #expect(isClose(result.regions[0].area, (s * (s - 31.7) * (s - 24.3) * (s - 25)).squareRoot(), tolerance: 1e-6))
    }

    @Test func anEmptySketchHasNoRegionsAndNoWarning() {
        let result = SketchRegions.find(in: Sketch())
        #expect(result.regions.isEmpty)
        #expect(result.warning == nil)
    }
}
