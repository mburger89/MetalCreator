import CreatorGeometry
import CreatorGraph
@testable import CreatorNodes
import CreatorSketch
import Testing

/// The Sketch node with splines: profiles carry spline segments, a self-crossing spline is warned about.
struct SplineSketchNodeTests {
    @Test func aLineAndASplineMakeAClosedProfileWithASplineSegment() throws {
        var sketch = Sketch()
        let start = sketch.addPoint(Vector2(0, 0))
        let end = sketch.addPoint(Vector2(10, 0))
        sketch.addLine(from: start, to: end)
        sketch.addSpline(through: [end, sketch.addPoint(Vector2(12, 5)), sketch.addPoint(Vector2(5, 8)), start])
        let output = try SketchSolve.run(sketch, on: .xy)
        #expect(output.profiles.count == 1)
        #expect(output.profiles[0].hasSpline)
    }

    @Test func selfCrossingSplineWarnsThroughTheNode() async throws {
        var sketch = Sketch()
        sketch.addSpline([Vector2(0, 0), Vector2(10, 10), Vector2(10, 0), Vector2(0, 10)])
        sketch.addLine(Vector2(30, 0), Vector2(40, 0))
        let output = try SketchSolve.run(sketch, on: .xy)
        #expect(output.warnings.contains("Spline 1 crosses itself, so it isn't part of a region."))
        #expect(output.profiles.isEmpty)
        #expect(!output.warnings.contains(SketchSolve.nothingDrawn))
    }
}
