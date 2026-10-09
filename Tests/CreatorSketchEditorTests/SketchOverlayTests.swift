import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// The sketch drawn over the viewport (sketcher spec §8's colour table): freedom colours, construction dashed, the
/// selection and hover over them, the rubber band, and the plane grid, all on the sketch's plane.
@MainActor
struct SketchOverlayTests {
    func tints(_ overlay: ViewportOverlay) -> Set<OverlayTint> { Set(overlay.lines.map(\.tint) + overlay.points.map(\.tint)) }

    @Test func aFullyConstrainedRectangleIsDrawnFixedOnItsPlane() {
        let model = SketchEditorModel(sketch: RectangleSketch().sketch, plane: .xz)
        let overlay = model.overlay
        #expect(overlay.lines.count == 4 && overlay.points.count == 4)
        #expect(tints(overlay) == [.fullyConstrained])
        #expect(overlay.gridPlane == .xz, "the plane grid replaces the ground grid")
        #expect(overlay.lines.allSatisfy { abs($0.a.y) < 1e-9 && abs($0.b.y) < 1e-9 }, "XZ: plane y is world z")
        #expect(overlay.lines.contains { abs($0.a.z - 40) < 1e-9 && abs($0.b.z - 40) < 1e-9 }, "the top edge is at z 40")
    }

    @Test func freeGeometryIsUnderConstrainedAndConflictsAreRed() {
        let free = SketchEditorModel(sketch: RectangleSketch(dimensioned: false).sketch, plane: .xy)
        #expect(tints(free.overlay).contains(.underConstrained))
        var conflicting = RectangleSketch()
        conflicting.sketch.add(.vertical(conflicting.lines[0]))
        let model = SketchEditorModel(sketch: conflicting.sketch, plane: .xy)
        #expect(model.overlay.lines.contains { $0.tint == .conflicting })
    }

    @Test func constructionIsDashedInItsOwnColour() throws {
        var sketch = Sketch()
        sketch.addLine(Vector2(0, 0), Vector2(10, 0), isConstruction: true)
        let line = try #require(SketchEditorModel(sketch: sketch, plane: .xy).overlay.lines.first)
        #expect(line.isDashed && line.tint == .construction)
    }

    @Test func theSelectionAndTheHoveredEntityAreDrawnOverTheirFreedom() {
        let rectangle = RectangleSketch()
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        model.selection = [rectangle.lines[0]]
        model.hovered = rectangle.corners[2]
        let overlay = model.overlay
        #expect(overlay.lines.filter { $0.tint == .selected }.count == 1)
        #expect(overlay.lines.first { $0.tint == .selected }?.width == SketchOverlayBuilder.selectedWidth)
        #expect(overlay.points.filter { $0.tint == .hovered }.count == 1)
    }

    @Test func circlesAndArcsAreSmoothPolylines() {
        var sketch = Sketch()
        sketch.addCircle(center: Vector2(0, 0), radius: 5)
        let centre = sketch.addPoint(Vector2(20, 0))
        let start = sketch.addPoint(Vector2(25, 0))
        let end = sketch.addPoint(Vector2(20, 5))
        sketch.addArc(center: centre, start: start, end: end)
        let overlay = SketchEditorModel(sketch: sketch, plane: .xy).overlay
        let circle = overlay.lines.filter { $0.a.x < 10 }
        #expect(circle.count == EditorGeometry.segmentsPerTurn)
        #expect(circle.allSatisfy { abs(Vector2($0.a.x, $0.a.y).length - 5) < 1e-9 })
        let arc = overlay.lines.filter { $0.a.x >= 10 }
        #expect(arc.count == EditorGeometry.segmentsPerTurn / 4, "a quarter turn")
    }

    @Test func theRubberBandIsDrawnFaded() {
        let model = SketchEditorModel(sketch: Sketch(), plane: .xy)
        model.preview = SketchPreview(curves: [.line(Vector2(0, 0), Vector2(5, 5))], points: [Vector2(0, 0)])
        let overlay = model.overlay
        #expect(overlay.lines.map(\.tint) == [.preview] && overlay.points.map(\.tint) == [.preview])
    }
}
