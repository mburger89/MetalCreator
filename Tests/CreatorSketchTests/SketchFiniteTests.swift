import CreatorGeometry
import Testing
@testable import CreatorSketch

/// S4: the graph stores a sketch as a setting in JSON, which can't hold NaN or ±∞.
struct SketchFiniteTests {
    @Test func aDrawnSketchIsFinite() {
        #expect(ConstrainedRectangle().sketch.isFinite)
    }

    @Test func aNonFinitePointRadiusOrPlaneIsNot() {
        var point = Sketch()
        point.addPoint(Vector2(.nan, 0))
        #expect(!point.isFinite)
        var circle = Sketch()
        circle.addCircle(center: .zero, radius: .infinity)
        #expect(!circle.isFinite)
        let plane = Sketch(plane: .fixed(Plane(origin: Vector3(0, .nan, 0), normal: .unitZ, xAxis: .unitX)))
        #expect(!plane.isFinite)
    }

    @Test func aNonFiniteDimensionFixOrWarmStartIsNot() {
        var dimension = ConstrainedRectangle().sketch
        dimension.dimensions[ConstrainedRectangle().width]?.value = .nan
        #expect(!dimension.isFinite)
        var fix = Sketch()
        let point = fix.addPoint(.zero)
        fix.add(.fix(point, at: Vector2(0, .infinity)))
        #expect(!fix.isFinite)
        var warm = Sketch()
        let moved = warm.addPoint(.zero)
        warm.solved[moved] = .point(Vector2(.nan, .nan))
        #expect(!warm.isFinite)
    }

    @Test func aNonFiniteProjectedCurveIsNot() {
        var sketch = Sketch()
        sketch.add(SketchEntity(.projected(ProjectionSource(reference: "p1", curve: .circle(center: .zero, radius: .nan)))))
        #expect(!sketch.isFinite)
    }
}
