import CreatorSketch
import CreatorViewport
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

    /// The chip's computed width holds its text: every glyph of the widest plausible readouts lies inside the chip.
    @Test(arguments: ["R 1234.5 mm · 359.9°", "-12345.6, -98765.4", "⌀ 99999.9 mm", "12345.6 mm · 359.9°"])
    func theChipHoldsItsText(_ text: String) throws {
        let chip = try #require(ReadoutChip(text: text, pointer: ScreenPoint(600, 350), in: ViewportSize(width: 1200, height: 700)))
        let scene = renderHeadless {
            ZStack(alignment: .topLeading) { ReadoutChipView(chip: chip) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        #expect(scene.glyphs.count >= text.filter { !$0.isWhitespace }.count - 1)
        for glyph in scene.glyphs {
            let minX = Double(glyph.bounds.origin.x) / 2
            let maxX = Double(glyph.bounds.origin.x + glyph.bounds.size.width) / 2
            let minY = Double(glyph.bounds.origin.y) / 2
            let maxY = Double(glyph.bounds.origin.y + glyph.bounds.size.height) / 2
            #expect(minX >= chip.origin.x && maxX <= chip.origin.x + chip.size.width
                    && minY >= chip.origin.y && maxY <= chip.origin.y + chip.size.height, "\(text): a glyph spills out")
        }
    }
}
