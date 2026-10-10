import CreatorSketch
import MetalUI
import Testing
@testable import CreatorSketchEditor

/// The command tools in the toolbar and their hints and options in the inspector, drawn headless. Looks and keys are
/// human checks (group S5b).
@MainActor
struct ToolOptionsViewTests {
    @Test func theToolbarHoldsEveryTool() {
        let drawing: [SketchTool] = [.select, .line, .arc, .arcThreePoint, .circle, .point, .dimension]
        #expect(SketchTool.allCases == drawing + [.trim, .extend, .fillet, .mirror, .pattern])
        let model = SketchEditorModel(sketch: RectangleSketch().sketch, plane: .xy)
        model.choose(.pattern)
        #expect(!renderHeadless { SketchToolbar(model: model) }.glyphs.isEmpty)
    }

    @Test func theCommandToolsSayWhatToDo() {
        let hinted = SketchTool.allCases.filter { $0.hint != nil }
        #expect(hinted == [.arcThreePoint, .trim, .extend, .fillet, .mirror, .pattern])
    }

    /// The glyphs `text` draws (one per character that isn't a space).
    func glyphs(_ text: String) -> Int {
        text.filter { !$0.isWhitespace }.count
    }

    /// The fillet and pattern options add their rows under the hint: the inspector draws at least the hint's glyphs
    /// and the fields' labels' more than with no tool hint (the fields' values come on top); Mirror shows only its hint.
    @Test(arguments: [(SketchTool.fillet, ["Radius"]), (.pattern, ["Instances", "Spacing"])])
    func theOptionsAddRows(_ tool: SketchTool, labels: [String]) throws {
        let model = SketchEditorModel(sketch: RectangleSketch().sketch, plane: .xy)
        model.choose(.select)
        let plain = renderHeadless { SketchInspector(model: model) }.glyphs.count
        model.choose(tool)
        let withOptions = renderHeadless { SketchInspector(model: model) }.glyphs.count
        let hint = try #require(tool.hint)
        #expect(withOptions >= plain + glyphs(hint) + glyphs(labels.joined()), "the hint and the fields")
        model.choose(.mirror)
        let hintOnly = renderHeadless { SketchInspector(model: model) }.glyphs.count
        #expect(hintOnly == plain + glyphs(try #require(SketchTool.mirror.hint)), "only the hint")
    }

    @Test func aToolsOptionReadsInMillimetres() {
        #expect(DimensionText.millimetres(5) == "5 mm")
        #expect(DimensionText.millimetres(2.5) == "2.5 mm")
        #expect(DimensionText.millimetres(1234.5) == "1234.5 mm")
    }
}
