import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// Splines in regions: the intersections, the loop measures, the region graph and the self-crossing rule.
struct SplineRegionTests {
    /// A spline through `positions` with its own fit points; returns the entity and the point entities.
    func spline(_ sketch: inout Sketch, _ positions: [Vector2]) -> (id: SketchEntityID, points: [SketchEntityID]) {
        let points = positions.map { sketch.addPoint($0) }
        return (sketch.addSpline(through: points), points)
    }

    /// The area of a spline-bounded loop by dense sampling of every segment (a reference independent of Green on B-splines).
    func sampledArea(_ segments: [Segment2D]) -> Double {
        var points: [Vector2] = []
        for segment in segments {
            switch segment {
            case .line(let a, _): points.append(a)
            case .spline(let curve):
                let range = curve.parameterRange
                points += (0..<4000).map { curve.point(at: range.lowerBound + (range.upperBound - range.lowerBound) * Double($0) / 4000) }
            case .arc: Issue.record("unexpected arc")
            }
        }
        return 0.5 * zip(points, points.dropFirst() + [points[0]]).reduce(0) { $0 + ($1.0.x * $1.1.y - $1.1.x * $1.0.y) }
    }

    @Test func aLineAndASplineCloseARegion() throws {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(0, 0), Vector2(10, 0))
        let (start, end) = sketch.ends(line)
        let middle = sketch.addPoint(Vector2(12, 5))
        let top = sketch.addPoint(Vector2(5, 8))
        let curve = sketch.addSpline(through: [end, middle, top, start])
        let result = SketchRegions.find(in: sketch)
        let region = try #require(result.regions.first)
        #expect(result.regions.count == 1 && result.openCurves.isEmpty)
        let profile = region.profile(on: .xy)
        #expect(profile.isClosed)
        #expect(region.outer.contains { $0.isSpline })
        #expect(isClose(region.area, sampledArea(region.outer), tolerance: 1e-3))
        #expect(Set(region.sources[0]) == [line, curve])
    }

    @Test func splinePiecesRejoinWhenADanglingCurveIsPruned() throws {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(0, 0), Vector2(10, 0))
        let (start, end) = sketch.ends(line)
        let curve = sketch.addSpline(through: [end, sketch.addPoint(Vector2(12, 5)), sketch.addPoint(Vector2(5, 8)), start])
        let before = try #require(SketchRegions.find(in: sketch).regions.first)
        _ = sketch.addLine(Vector2(5, 3), Vector2(5, 14))
        let result = SketchRegions.find(in: sketch)
        let region = try #require(result.regions.first)
        #expect(result.regions.count == 1)
        #expect(region.outer.count == 2 && region.outer.filter(\.isSpline).count == 1)
        #expect(isClose(region.area, before.area, tolerance: 1e-9))
        let joined = try #require(region.outer.first { $0.isSpline })
        let original = try #require(before.outer.first { $0.isSpline })
        #expect(joined == original)
        let trace = SketchTrace(sketch: sketch, regionSources: [region.sources])
        for (index, segment) in region.outer.enumerated() {
            #expect(trace.entity(item: 0, loop: 0, segment: index) == (segment.isSpline ? curve : line))
        }
    }

    @Test func aSplineSplitByARealBoundaryStaysSplit() throws {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(0, 0), Vector2(10, 0))
        let (start, end) = sketch.ends(line)
        _ = sketch.addSpline(through: [end, sketch.addPoint(Vector2(12, 5)), sketch.addPoint(Vector2(5, 8)), start])
        _ = sketch.addLine(Vector2(5, -3), Vector2(5, 14))
        let result = SketchRegions.find(in: sketch)
        #expect(result.regions.count == 2)
        for region in result.regions { #expect(region.outer.filter(\.isSpline).count == 1) }
    }

    @Test func twoSplinesCloseARegion() throws {
        var sketch = Sketch()
        let a = sketch.addPoint(Vector2(0, 0))
        let b = sketch.addPoint(Vector2(10, 0))
        let upper = sketch.addSpline(through: [a, sketch.addPoint(Vector2(5, 4)), b])
        let lower = sketch.addSpline(through: [a, sketch.addPoint(Vector2(5, -4)), b])
        let result = SketchRegions.find(in: sketch)
        let region = try #require(result.regions.first)
        #expect(result.regions.count == 1)
        #expect(region.profile(on: .xy).isClosed)
        #expect(region.outer.count == 2 && region.outer.allSatisfy(\.isSpline))
        #expect(Set(region.sources[0]) == [upper, lower])
        #expect(isClose(region.area, sampledArea(region.outer), tolerance: 1e-3))
        #expect(region.area > 0)
    }

    @Test func aSplineCrossingACircleSplitsRegions() throws {
        var sketch = Sketch()
        sketch.addCircle(center: Vector2(5, 0), radius: 3)
        let (curve, _) = spline(&sketch, [Vector2(5, -6), Vector2(6, 0), Vector2(5, 6)])
        let result = SketchRegions.find(in: sketch)
        #expect(result.regions.count == 2, "the circle in two halves; the spline's tails dangle")
        #expect(isClose(result.regions.reduce(0) { $0 + $1.area }, 9 * Double.pi, tolerance: 1e-6))
        for region in result.regions {
            #expect(region.profile(on: .xy).isClosed)
            #expect(region.sources[0].contains(curve))
        }
    }

    @Test func selfCrossingWarnsAndIsLeftOut() throws {
        var sketch = Sketch()
        _ = addPolygon(&sketch, [Vector2(30, 0), Vector2(40, 0), Vector2(40, 10)])
        let (curve, _) = spline(&sketch, [Vector2(0, 0), Vector2(10, 10), Vector2(10, 0), Vector2(0, 10)])
        let result = SketchRegions.find(in: sketch)
        #expect(result.selfCrossingSplines == [curve])
        #expect(result.selfCrossingWarnings == ["Spline 1 crosses itself, so it isn't part of a region."])
        #expect(result.regions.count == 1, "the triangle only")
        #expect(!result.openCurves.contains(curve))
    }

    @Test func aSplineWithoutACrossingDoesNotWarn() {
        var sketch = Sketch()
        _ = spline(&sketch, [Vector2(0, 0), Vector2(5, 3), Vector2(10, 0)])
        #expect(SketchRegions.find(in: sketch).selfCrossingWarnings.isEmpty)
    }

    @Test func traceMapsSplineSegmentsToTheEntity() throws {
        var sketch = Sketch()
        let a = sketch.addPoint(Vector2(0, 0))
        let b = sketch.addPoint(Vector2(10, 0))
        let upper = sketch.addSpline(through: [a, sketch.addPoint(Vector2(5, 4)), b])
        let line = sketch.addLine(from: a, to: b)
        let region = try #require(SketchRegions.find(in: sketch).regions.first)
        let trace = SketchTrace(sketch: sketch, regionSources: [region.sources])
        for (index, segment) in region.outer.enumerated() {
            #expect(trace.entity(item: 0, loop: 0, segment: index) == (segment.isSpline ? upper : line))
        }
    }

    // MARK: Intersections

    @Test func aSplineMeetsALineToTheTolerance() throws {
        var sketch = Sketch()
        let (curve, _) = spline(&sketch, [Vector2(0, 0), Vector2(5, 6), Vector2(10, 0)])
        let line = sketch.addLine(Vector2(-1, 3), Vector2(11, 3))
        let (a, b) = try (#require(sketch.shape(of: curve)), #require(sketch.shape(of: line)))
        let points = CurveIntersection.points(a, b)
        #expect(points.count == 2)
        for point in points {
            #expect(abs(point.y - 3) < 1e-10)
            #expect(a.contains(point, tolerance: 1e-9))
        }
    }

    @Test func aSplineMeetsAnArcAndASpline() throws {
        var sketch = Sketch()
        let (curve, _) = spline(&sketch, [Vector2(0, 0), Vector2(5, 6), Vector2(10, 0)])
        let circle = sketch.addCircle(center: Vector2(5, 0), radius: 5.5)
        let (other, _) = spline(&sketch, [Vector2(0, 5), Vector2(5, -2), Vector2(10, 5)])
        let (a, c, d) = try (#require(sketch.shape(of: curve)), #require(sketch.shape(of: circle)), #require(sketch.shape(of: other)))
        for point in CurveIntersection.points(a, c) {
            #expect(abs((point - Vector2(5, 0)).length - 5.5) < 1e-9)
        }
        #expect(CurveIntersection.points(a, c).count == 2)
        let crossings = CurveIntersection.points(a, d)
        #expect(crossings.count == 2)
        for point in crossings { #expect(a.contains(point, tolerance: 1e-9) && d.contains(point, tolerance: 1e-9)) }
    }

    @Test func aTangentTouchIsFoundOnce() throws {
        var sketch = Sketch()
        // A symmetric arch whose top, (5, 4), lies on the line y = 4 and is tangent to it.
        let (curve, _) = spline(&sketch, [Vector2(0, 0), Vector2(5, 4), Vector2(10, 0)])
        let line = sketch.addLine(Vector2(-1, 4), Vector2(11, 4))
        let (a, b) = try (#require(sketch.shape(of: curve)), #require(sketch.shape(of: line)))
        let points = CurveIntersection.points(a, b)
        #expect(points.count == 1, "\(points)")
        #expect(points.allSatisfy { abs($0.y - 4) < 1e-6 })
    }

    @Test func piecesOfASplineKeepItsGeometry() throws {
        var sketch = Sketch()
        let (curve, _) = spline(&sketch, [Vector2(0, 0), Vector2(5, 6), Vector2(10, 0), Vector2(14, 5)])
        let shape = try #require(sketch.shape(of: curve))
        let end = shape.parameterEnd
        let piece = shape.piece(from: 0.3 * end, to: 0.8 * end)
        #expect(isClose(piece.startPoint, shape.point(at: 0.3 * end), tolerance: 1e-9))
        #expect(isClose(piece.endPoint, shape.point(at: 0.8 * end), tolerance: 1e-9))
        #expect(isClose(piece.point(at: piece.parameterEnd / 2), shape.point(at: 0.55 * end), tolerance: 1e-9))
        let (whole, parts) = (shape.length(from: 0, to: end), shape.length(from: 0, to: 0.3 * end) + shape.length(from: 0.3 * end, to: end))
        #expect(abs(whole - parts) < 1e-6, "whole \(whole) parts \(parts)")
        guard case .spline(let curve) = shape else { Issue.record("not a spline"); return }
        #expect(abs(whole - curve.length) < 1e-6, "whole \(whole) curve \(curve.length)")
    }

    @Test func loopMeasuresAreExactForASplineLoop() throws {
        var sketch = Sketch()
        let a = sketch.addPoint(Vector2(0, 0))
        let b = sketch.addPoint(Vector2(10, 0))
        _ = sketch.addSpline(through: [a, sketch.addPoint(Vector2(5, 4)), b])
        sketch.addSpline(through: [b, sketch.addPoint(Vector2(5, -4)), a])
        let region = try #require(SketchRegions.find(in: sketch).regions.first)
        // The centroid of a lens symmetric about y = 0 and x = 5.
        #expect(abs(region.centroid.x - 5) < 1e-6 && abs(region.centroid.y) < 1e-6)
    }
}
