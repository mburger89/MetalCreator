import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Double-clicking a Sketch node opens its sketch (sketcher spec §8), as its "Edit sketch" button does: a second click
/// with no modifiers on the same node, which the platform counted as the second of a double click
/// (`DragGesture.Value.clickCount`, MetalUI C16, gap S5-b).
@MainActor
struct DoubleClickTests {
    func makeSketchEditor() -> (EditorModel, Node, Node) {
        let sketch = testNode(SketchTestNode.self, id: 1, at: .zero, registry: sketchTestRegistry)
        let number = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0), registry: sketchTestRegistry)
        let editor = makeEditor([sketch, number], registry: sketchTestRegistry)
        return (editor, sketch, number)
    }

    @Test func aDoubleClickOnASketchNodeAsksToEditIt() throws {
        let (editor, sketch, _) = makeSketchEditor()
        let point = editor.screenPoint(in: sketch.id)
        editor.click(point)
        #expect(editor.inspectorRequest == nil, "one click only selects")
        editor.click(point + Vector2(2, 1), clickCount: 2)
        let request = try #require(editor.inspectorRequest)
        #expect(request.node == sketch.id && request.action == .editSketch)
        #expect(editor.selection == [sketch.id])
    }

    /// The count is the platform's, so how slow or wide a double click may be is the user's setting: the model asks
    /// for no time and no distance of its own (the groups spec's 0.4 s and 4 points were a stand-in until C16).
    @Test func theModelAddsNoTimeOrDistanceOfItsOwn() throws {
        let (editor, sketch, _) = makeSketchEditor()
        let point = editor.screenPoint(in: sketch.id)
        editor.click(point)
        editor.click(point + Vector2(12, 0), clickCount: 2)
        #expect(editor.inspectorRequest?.action == .editSketch, "the platform counted it, however far or slow")
    }

    /// Count 3 and up are no double click, and a count-3 click is not the first of the next pair.
    @Test func aThirdClickIsNotADoubleClickAndStartsNoPair() {
        let (editor, sketch, _) = makeSketchEditor()
        let point = editor.screenPoint(in: sketch.id)
        editor.click(point)
        editor.click(point, clickCount: 2)
        let first = editor.inspectorRequest?.serial
        editor.click(point, clickCount: 3)
        editor.click(point, clickCount: 4)
        #expect(editor.inspectorRequest?.serial == first, "counts 3 and 4 ask for nothing")
        editor.click(point, clickCount: 2)
        #expect(editor.inspectorRequest?.serial == first, "and a count 2 after them has no first click to pair with")
        editor.click(point)
        editor.click(point, clickCount: 2)
        #expect(editor.inspectorRequest?.serial != first, "a new first click starts a new pair")
    }

    /// Review Focus 5: two clicks that aren't a double click (the platform counted the second as a new first click, on
    /// two nodes, a modifier held, a count 2 with no first click, or a drag between) never open the sketch.
    @Test func clicksThatArentADoubleClickDoNothing() {
        let (editor, sketch, number) = makeSketchEditor()
        let point = editor.screenPoint(in: sketch.id)
        editor.click(point)
        editor.click(point)
        #expect(editor.inspectorRequest == nil, "too slow or too far for the platform: both count 1")
        editor.click(editor.screenPoint(in: number.id))
        editor.click(point, clickCount: 2)
        #expect(editor.inspectorRequest == nil, "two nodes")
        for modifiers: CanvasModifiers in [.shift, .command] {
            editor.click(point, modifiers: modifiers)
            editor.click(point, modifiers: modifiers, clickCount: 2)
            #expect(editor.inspectorRequest == nil, "⇧ extends and ⌘ toggles the selection instead")
        }
        editor.click(point)
        editor.click(point, modifiers: .shift, clickCount: 2)
        #expect(editor.inspectorRequest == nil, "a modifier on the second click only")
        editor.click(Vector2(700, 600))
        editor.click(point, clickCount: 2)
        #expect(editor.inspectorRequest == nil, "a count 2 whose first click was elsewhere")
        editor.click(point)
        editor.drag(point, point + Vector2(40, 0))
        editor.click(point + Vector2(40, 0), clickCount: 2)
        #expect(editor.inspectorRequest == nil, "a drag between")
    }

    @Test func aDoubleClickOnAnotherNodeOnlySelectsIt() {
        let (editor, _, number) = makeSketchEditor()
        let point = editor.screenPoint(in: number.id)
        editor.doubleClick(point)
        #expect(editor.inspectorRequest == nil)
        #expect(editor.selection == [number.id])
    }

    @Test func aDoubleClickOnEmptyCanvasDoesNothing() {
        let (editor, _, _) = makeSketchEditor()
        editor.doubleClick(Vector2(700, 600))
        #expect(editor.inspectorRequest == nil)
    }

    /// The recogniser is generic: what a double click presses is looked up per node (the groups editor adds "Edit
    /// Group" to `doubleClickActions`).
    @Test func whatADoubleClickPressesIsPerNode() {
        let (editor, sketch, number) = makeSketchEditor()
        #expect(editor.doubleClickAction(for: sketch.id) == .editSketch)
        #expect(editor.doubleClickAction(for: number.id) == nil)
    }

    /// The count rides the press's first value, as `GraphPanelInput` reads it from MetalUI's drag value (the same for
    /// every value of one press).
    @Test func theCountOfAPressIsItsFirstValuesNotTheReleases() {
        let (editor, sketch, _) = makeSketchEditor()
        let point = editor.screenPoint(in: sketch.id)
        editor.click(point)
        editor.pointerDragged(from: point, to: point, clickCount: 2)
        editor.pointerReleased(from: point, at: point, clickCount: 1)
        #expect(editor.inspectorRequest?.action == .editSketch)
    }
}
