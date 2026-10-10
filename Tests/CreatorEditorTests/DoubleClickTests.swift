import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Double-clicking a Sketch node opens its sketch (sketcher spec §8), as its "Edit sketch" button does: two clicks
/// with no modifiers on the same node, close together in time and place.
@MainActor
struct DoubleClickTests {
    func makeSketchEditor() -> (EditorModel, Node, Node, TestClock) {
        let sketch = testNode(SketchTestNode.self, id: 1, at: .zero, registry: sketchTestRegistry)
        let number = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0), registry: sketchTestRegistry)
        let editor = makeEditor([sketch, number], registry: sketchTestRegistry)
        let clock = TestClock()
        editor.now = { clock.now }
        return (editor, sketch, number, clock)
    }

    @Test func aDoubleClickOnASketchNodeAsksToEditIt() throws {
        let (editor, sketch, _, clock) = makeSketchEditor()
        let point = editor.screenPoint(in: sketch.id)
        editor.click(point)
        #expect(editor.inspectorRequest == nil, "one click only selects")
        clock.advance(by: .milliseconds(200))
        editor.click(point + Vector2(2, 1))
        let request = try #require(editor.inspectorRequest)
        #expect(request.node == sketch.id && request.action == .editSketch)
        #expect(editor.selection == [sketch.id])
    }

    @Test func aThirdClickStartsANewPair() {
        let (editor, sketch, _, clock) = makeSketchEditor()
        let point = editor.screenPoint(in: sketch.id)
        editor.click(point)
        editor.click(point)
        let first = editor.inspectorRequest?.serial
        clock.advance(by: .milliseconds(100))
        editor.click(point)
        #expect(editor.inspectorRequest?.serial == first, "the third click is the first of the next pair")
    }

    /// Review Focus 5: two clicks that aren't a double click (too slow, too far apart, on two nodes, a modifier held,
    /// or with a drag between) never open the sketch.
    @Test func clicksThatArentADoubleClickDoNothing() {
        let (editor, sketch, number, clock) = makeSketchEditor()
        let point = editor.screenPoint(in: sketch.id)
        editor.click(point)
        clock.advance(by: .milliseconds(450))
        editor.click(point)
        #expect(editor.inspectorRequest == nil, "too slow")
        clock.advance(by: .seconds(1))
        editor.click(point)
        editor.click(point + Vector2(6, 0))
        #expect(editor.inspectorRequest == nil, "too far apart")
        clock.advance(by: .seconds(1))
        editor.click(editor.screenPoint(in: number.id))
        editor.click(point)
        #expect(editor.inspectorRequest == nil, "two nodes")
        for modifiers: CanvasModifiers in [.shift, .command] {
            clock.advance(by: .seconds(1))
            editor.click(point, modifiers: modifiers)
            editor.click(point, modifiers: modifiers)
            #expect(editor.inspectorRequest == nil, "⇧ extends and ⌘ toggles the selection instead")
        }
        clock.advance(by: .seconds(1))
        editor.click(point)
        editor.drag(point, point + Vector2(40, 0))
        editor.click(point + Vector2(40, 0))
        #expect(editor.inspectorRequest == nil, "a drag between")
    }

    @Test func aDoubleClickOnAnotherNodeOnlySelectsIt() {
        let (editor, _, number, _) = makeSketchEditor()
        let point = editor.screenPoint(in: number.id)
        editor.click(point)
        editor.click(point)
        #expect(editor.inspectorRequest == nil)
        #expect(editor.selection == [number.id])
    }

    @Test func aDoubleClickOnEmptyCanvasDoesNothing() {
        let (editor, _, _, _) = makeSketchEditor()
        editor.click(Vector2(700, 600))
        editor.click(Vector2(700, 600))
        #expect(editor.inspectorRequest == nil)
    }

    /// The recogniser is generic: what a double click presses is looked up per node (the groups editor adds "Edit
    /// Group" to `doubleClickActions`).
    @Test func whatADoubleClickPressesIsPerNode() {
        let (editor, sketch, number, _) = makeSketchEditor()
        #expect(editor.doubleClickAction(for: sketch.id) == .editSketch)
        #expect(editor.doubleClickAction(for: number.id) == nil)
    }
}
