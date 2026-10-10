import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// The overlay carries one fill per closed region (sketcher spec §8: "Output regions: faint green fill").
@MainActor
struct RegionFillTests {
    /// The area the fill's triangles cover (in the plane's xy).
    func area(_ fill: OverlayFill) -> Double {
        stride(from: 0, to: fill.vertices.count - 2, by: 3).reduce(0) { sum, index in
            let (a, b, c) = (fill.vertices[index], fill.vertices[index + 1], fill.vertices[index + 2])
            return sum + abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2
        }
    }

    @Test func aClosedShapeIsOneRegionFill() throws {
        let model = SketchEditorModel(sketch: RectangleSketch().sketch, plane: .xy)
        let fill = try #require(model.overlay.fills.first)
        #expect(model.overlay.fills.count == 1 && fill.tint == .region)
        #expect(fill.vertices.count == 6 && abs(area(fill) - 2400) < 1e-9)
    }

    @Test func aHoleIsLeftEmptyAndAnIslandInItIsItsOwnRegion() {
        var sketch = RectangleSketch().sketch
        sketch.addCircle(center: Vector2(30, 20), radius: 12)
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        #expect(model.overlay.fills.count == 1)
        let ring = Double.pi * 144
        #expect(abs(area(model.overlay.fills[0]) - (2400 - ring)) < 0.01 * ring, "the circle's polygon, not the disc")
        sketch.addCircle(center: Vector2(30, 20), radius: 4)
        let island = SketchEditorModel(sketch: sketch, plane: .xy)
        #expect(island.overlay.fills.count == 2, "the rectangle with the big circle cut out, and the small disc")
    }

    @Test func openCurvesAndConstructionMakeNoFill() {
        var open = Sketch()
        open.addLine(Vector2(0, 0), Vector2(10, 0))
        open.addLine(Vector2(10, 0), Vector2(10, 10))
        #expect(SketchEditorModel(sketch: open, plane: .xy).overlay.fills.isEmpty)
        var construction = RectangleSketch().sketch
        for id in construction.entityIDs { construction.entities[id]?.isConstruction = true }
        #expect(SketchEditorModel(sketch: construction, plane: .xy).overlay.fills.isEmpty)
    }

    @Test func theFillLiesOnThePlane() throws {
        let model = SketchEditorModel(sketch: RectangleSketch().sketch, plane: .xz)
        let fill = try #require(model.overlay.fills.first)
        #expect(fill.vertices.allSatisfy { $0.y == 0 }, "the xz plane: y is the normal")
        #expect(fill.vertices.contains(Vector3(60, 0, 40)))
    }

    @Test func theFillFollowsEditsAndIsFoundOncePerSketch() throws {
        let model = SketchEditorModel(sketch: Sketch(), plane: .xy)
        #expect(model.overlay.fills.isEmpty)
        let host = RecordingHost(model)
        model.choose(.line)
        for corner in [Vector2(0, 0), Vector2(30, 0), Vector2(30, 20), Vector2(0, 20), Vector2(0, 0)] {
            model.click(at: corner, tolerance: 0.5, modifiers: [])
        }
        #expect(host.commits.count == 4)
        let first = model.overlay.fills
        #expect(first.count == 1 && abs(area(first[0]) - 600) < 1e-9, "the fourth line closes the rectangle")
        #expect(model.fillCache?.sketch == model.sketch, "kept for this sketch")
        model.hover(at: Vector2(50, 50), tolerance: 0.5, modifiers: [])
        #expect(model.overlay.fills == first, "a hover doesn't change it")
    }
}
