import CreatorSketch
import MetalUI
import Testing
@testable import CreatorSketchEditor

/// Headless frames of the toolbar and the inspector: they build, lay out and paint in each state. Looks and keys are
/// human checks (group S5; a client can't send keys through a window, docs/metalui-gaps.md M6-e).
@MainActor
struct SketchViewTests {
    @Test func theToolKeysAreTheSpecs() {
        #expect(SketchTool.line.key == "l" && SketchTool.arc.key == "a" && SketchTool.circle.key == "c")
        #expect(SketchTool.dimension.key == "d" && SketchTool.select.key == nil && SketchTool.point.key == nil)
    }

    @Test func theToolbarAndTheConstraintButtonsDrawWithAndWithoutASelection() {
        let rectangle = RectangleSketch()
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        #expect(!renderHeadless { SketchToolbar(model: model) }.glyphs.isEmpty)
        model.selection = [rectangle.lines[0], rectangle.lines[1]]
        model.toggleConstruction()
        #expect(!renderHeadless { SketchToolbar(model: model) }.glyphs.isEmpty)
        #expect(!renderHeadless { SketchInspector(model: model) }.glyphs.isEmpty)
    }

    @Test func theInspectorDrawsDimensionsConstraintsAndProblems() {
        var rectangle = RectangleSketch()
        rectangle.sketch.add(.vertical(rectangle.lines[0]))
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        model.refusal = "Select two lines."
        #expect(!renderHeadless { SketchInspector(model: model) }.glyphs.isEmpty)
        let empty = SketchEditorModel(sketch: Sketch(), plane: .xy)
        #expect(!renderHeadless { SketchInspector(model: empty) }.glyphs.isEmpty)
    }
}
