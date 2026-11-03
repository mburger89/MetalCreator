import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// Deleting a fit point takes just that point out of the spline while two or more remain.
struct SplineFitPointDeletionTests {
    func fourPoints() -> (sketch: Sketch, spline: SketchEntityID, points: [SketchEntityID]) {
        var sketch = Sketch()
        let points = [Vector2(0, 0), Vector2(4, 3), Vector2(9, 1), Vector2(12, 6)].map { sketch.addPoint($0) }
        let spline = sketch.addSpline(through: points)
        return (sketch, spline, points)
    }

    @Test func anInteriorPointLeavesTheSplineShorterWithItsHandleGone() throws {
        var (sketch, spline, points) = fourPoints()
        sketch.activateSplineHandle(spline, at: 1, .tangent)
        sketch.activateSplineHandle(spline, at: 2, .curvature)
        let dimension = sketch.addDimension(.distance(points[1], points[2]), value: 5)
        sketch.removeEntity(points[1])
        let parts = try #require(sketch.splineParts(of: spline))
        #expect(parts.points == [points[0], points[2], points[3]])
        #expect(parts.handles == [.automatic, SplineHandleState(tangent: false, curvature: true), .automatic])
        #expect(sketch.dimensions[dimension] == nil)
        #expect(sketch.entities[points[1]] == nil)
        let definition = try #require(sketch.splineDefinition(of: spline))
        #expect(definition.points.count == 3 && definition.handles.count == 3)
        #expect(definition.handles[0].tangent == nil && definition.handles[1].curvature != nil)
    }

    @Test func anEndPointLeavesTheSplineShorter() throws {
        var (sketch, spline, points) = fourPoints()
        sketch.removeEntity(points[3])
        #expect(sketch.splineParts(of: spline)?.points == Array(points[0..<3]))
        sketch.removeEntity(points[0])
        #expect(sketch.splineParts(of: spline)?.points == Array(points[1..<3]))
    }

    @Test func aTwoPointSplineGoesWithEitherPoint() {
        var sketch = Sketch()
        let a = sketch.addPoint(Vector2(0, 0))
        let b = sketch.addPoint(Vector2(5, 5))
        let spline = sketch.addSpline(through: [a, b])
        sketch.removeEntity(b)
        #expect(sketch.entities[spline] == nil && sketch.entities[b] == nil)
        #expect(sketch.entities[a] != nil)
    }

    @Test func aJointConstraintLostWithItsSharedEndGoes() {
        var (sketch, spline, points) = fourPoints()
        let line = sketch.addLine(from: points[3], to: sketch.addPoint(Vector2(20, 6)))
        sketch.activateSplineHandle(spline, at: 3, .tangent)
        let tangent = sketch.add(.tangent(spline, line))
        sketch.removeEntity(points[3])
        #expect(sketch.constraints[tangent] == nil)
        #expect(sketch.splineParts(of: spline)?.points.count == 3)
    }
}
