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
}
