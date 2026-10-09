import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// While it is the viewport's tool the editor locks the camera to its plane (planar navigation), and F frames the
/// sketch.
@MainActor
struct SketchNavigationTests {
    @Test func theEditorAsksForPlanarNavigation() {
        let model = SketchEditorModel(sketch: RectangleSketch().sketch, plane: .xy)
        #expect(model.navigation == .planar)
    }

    @Test func fFramesTheSketchsPointsWithAMargin() throws {
        let plane = Plane(origin: Vector3(0, 0, 5), normal: .unitZ, xAxis: .unitX)
        let model = SketchEditorModel(sketch: RectangleSketch().sketch, plane: plane)
        let bounds = try #require(model.framingBounds)
        #expect((bounds.min - Vector3(-6, -4, 5)).length < 1e-9, "60 × 40 and 10% on each side, on the plane")
        #expect((bounds.max - Vector3(66, 44, 5)).length < 1e-9)
    }

    @Test func anEmptySketchFrames100MillimetresAroundThePlanesOrigin() throws {
        let model = SketchEditorModel(sketch: Sketch(), plane: .xy)
        let bounds = try #require(model.framingBounds)
        #expect(bounds.min == Vector3(-50, -50, 0) && bounds.max == Vector3(50, 50, 0))
    }

    /// A circle's centre alone would leave the circle off screen: F frames the whole curve.
    @Test func fFramesALoneCircleWhole() throws {
        var sketch = Sketch()
        sketch.addCircle(center: Vector2(200, 200), radius: 30)
        let bounds = try #require(SketchEditorModel(sketch: sketch, plane: .xy).framingBounds)
        #expect(bounds.min.x <= 170 && bounds.min.y <= 170 && bounds.max.x >= 230 && bounds.max.y >= 230)
        #expect(bounds.max.x < 240, "with the margin, not the 100 mm fallback around the origin")
    }

    @Test func fFramesAnArcsCircle() throws {
        var sketch = Sketch()
        let center = sketch.addPoint(Vector2(100, 0))
        let start = sketch.addPoint(Vector2(110, 0))
        let end = sketch.addPoint(Vector2(100, 10))
        sketch.addArc(center: center, start: start, end: end)
        let bounds = try #require(SketchEditorModel(sketch: sketch, plane: .xy).framingBounds)
        #expect(bounds.min.x <= 90 && bounds.min.y <= -10 && bounds.max.x >= 110 && bounds.max.y >= 10)
    }
}
