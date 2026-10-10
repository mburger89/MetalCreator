import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// MetalUI's `Slider(onEditingChanged:)` (gap M5-a) tells the editor where a drag begins and ends, so each drag is
/// exactly one undo step, however the drags follow one another.
@MainActor
struct SliderEditingTests {
    let rect = testNode(RectangleTestNode.self, id: 1, at: .zero)

    func widthField(_ editor: EditorModel) -> InputField? {
        editor.selection = [rect.id]
        guard case .slider(let field, _)? = editor.inspectorPage.sections.first?.rows.first else { return nil }
        return field
    }

    /// One slider drag as MetalUI reports it: editing begins, each move writes, editing ends.
    func drag(_ editor: EditorModel, _ field: InputField, through values: [Double]) {
        editor.sliderEditingChanged(true)
        for value in values { editor.setNumber(field, to: value, continuous: true) }
        editor.sliderEditingChanged(false)
    }

    @Test func aDragFromPressToReleaseIsOneUndoStep() throws {
        let editor = makeEditor([rect])
        let field = try #require(widthField(editor))
        drag(editor, field, through: [11, 12, 13, 14])
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == .number(14))
        editor.document.undo()
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == nil)
        #expect(!editor.document.canUndo)
    }

    @Test func twoDragsWithNothingBetweenThemAreTwoUndoSteps() throws {
        let editor = makeEditor([rect])
        let field = try #require(widthField(editor))
        drag(editor, field, through: [11, 12])
        drag(editor, field, through: [13, 14])
        editor.document.undo()
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == .number(12))
        editor.document.undo()
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == nil)
        #expect(!editor.document.canUndo)
    }

    @Test func aTypedValueAfterTheReleaseIsItsOwnStep() throws {
        let editor = makeEditor([rect])
        let field = try #require(widthField(editor))
        drag(editor, field, through: [11, 12])
        editor.setNumber(field, to: 20)
        editor.document.undo()
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == .number(12))
    }

    @Test func aPressWithoutAChangeLeavesNoUndoStep() throws {
        let editor = makeEditor([rect])
        let field = try #require(widthField(editor))
        drag(editor, field, through: [])
        #expect(!editor.document.canUndo)
    }

    @Test func aParameterSliderDragIsOneStepAndTwoDragsAreTwo() {
        let width = GraphParameter(name: "Width", type: .number, value: .number(60))
        let editor = makeEditor([], parameters: [width])
        for values in [[61.0, 70], [80.0, 90]] {
            editor.sliderEditingChanged(true)
            for value in values { editor.setParameterNumber(width.id, to: value, continuous: true) }
            editor.sliderEditingChanged(false)
        }
        editor.document.undo()
        #expect(editor.graph.parameters.first?.value == .number(70))
        editor.document.undo()
        #expect(editor.graph.parameters.first?.value == .number(60))
        #expect(!editor.document.canUndo)
    }
}
