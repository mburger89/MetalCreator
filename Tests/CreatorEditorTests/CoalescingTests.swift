import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

@MainActor
struct CoalescingTests {
    let rect = testNode(RectangleTestNode.self, id: 1, at: .zero)
    let other = testNode(RectangleTestNode.self, id: 2, at: Vector2(0, 300))

    func widthField(_ editor: EditorModel, _ node: NodeID) -> InputField? {
        editor.selection = [node]
        guard case .slider(let field, _)? = editor.inspectorPage.sections.first?.rows.first else { return nil }
        return field
    }

    @Test func aSliderDragIsOneUndoStep() throws {
        let editor = makeEditor([rect])
        let field = try #require(widthField(editor, rect.id))
        for value in [11.0, 12, 13, 14] { editor.setInput(field, to: .number(value), continuous: true) }
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == .number(14))
        editor.document.undo()
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == nil)
        #expect(!editor.document.canUndo)
    }

    @Test func changingTheSelectionEndsTheDrag() throws {
        let editor = makeEditor([rect, other])
        let field = try #require(widthField(editor, rect.id))
        editor.setInput(field, to: .number(11), continuous: true)
        editor.selection = [other.id]
        editor.selection = [rect.id]
        editor.setInput(field, to: .number(12), continuous: true)
        editor.document.undo()
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == .number(11))
    }

    @Test func pressingTheCanvasEndsTheDrag() throws {
        let editor = makeEditor([rect])
        let field = try #require(widthField(editor, rect.id))
        editor.setInput(field, to: .number(11), continuous: true)
        editor.click(Vector2(900, 900))
        editor.selection = [rect.id]
        editor.setInput(field, to: .number(12), continuous: true)
        editor.document.undo()
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == .number(11))
    }

    @Test func typedValuesAreEachTheirOwnStep() throws {
        let editor = makeEditor([rect])
        let field = try #require(widthField(editor, rect.id))
        editor.setInput(field, to: .number(11))
        editor.setInput(field, to: .number(12))
        editor.document.undo()
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == .number(11))
    }

    @Test func settingTheSameValueRecordsNothing() throws {
        let editor = makeEditor([rect])
        let field = try #require(widthField(editor, rect.id))
        editor.setInput(field, to: .number(10))
        #expect(!editor.document.canUndo)
    }

    @Test func aNonFiniteValueIsRefusedWithAMessage() throws {
        let editor = makeEditor([rect])
        let field = try #require(widthField(editor, rect.id))
        editor.setInput(field, to: .number(.infinity))
        #expect(editor.refusal?.message == "Enter a finite number.")
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == nil)
    }

    @Test func aParameterDragIsOneUndoStep() {
        let width = GraphParameter(name: "Width", type: .number, value: .number(60))
        let editor = makeEditor([], parameters: [width])
        for value in [61.0, 70, 90] { editor.setParameter(width.id, to: .number(value), continuous: true) }
        #expect(editor.graph.parameters.first?.value == .number(90))
        editor.document.undo()
        #expect(editor.graph.parameters.first?.value == .number(60))
        #expect(!editor.document.canUndo)
    }

    @Test func aParameterOfTheWrongTypeIsRefused() {
        let count = GraphParameter(name: "Hole count", type: .integer, value: .integer(4))
        let editor = makeEditor([], parameters: [count])
        editor.setParameter(count.id, to: .number(4.5))
        #expect(editor.refusal != nil)
        #expect(editor.graph.parameters.first?.value == .integer(4))
    }

    @Test func aHugeWholeNumberIsRefusedNotTrapped() {
        let editor = makeEditor([rect])
        editor.selection = [rect.id]
        guard case .anchorGrid(let anchor, _)? = editor.inspectorPage.sections.last?.rows.last else {
            Issue.record("no anchor grid"); return
        }
        editor.setNumber(anchor, to: 1e300)
        #expect(editor.refusal?.message == "Enter a whole number.")
        #expect(editor.graph.nodes[rect.id]?.inputValues["anchor"] == nil)
        editor.setNumber(anchor, to: 2.4)
        #expect(editor.graph.nodes[rect.id]?.inputValues["anchor"] == .integer(2))
    }

    @Test func aWholeNumberParameterRoundsAndRefusesHugeValues() {
        let count = GraphParameter(name: "Hole count", type: .integer, value: .integer(4))
        let editor = makeEditor([], parameters: [count])
        editor.setParameterNumber(count.id, to: 6.4)
        #expect(editor.graph.parameters.first?.value == .integer(6))
        editor.setParameterNumber(count.id, to: -1e300)
        #expect(editor.refusal?.message == "Enter a whole number.")
        #expect(editor.graph.parameters.first?.value == .integer(6))
    }
}
