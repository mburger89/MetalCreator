import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// The middle mouse button pans the graph canvas (the user's Gate G answer (b), 2026-10-09: a plain drag box-selects,
/// so the pan moves to two-finger scroll and the middle button), as it pans the viewport (VC3). It pans wherever it
/// starts, nodes included, and never selects, moves or edits anything. As in the viewport, a middle press during a
/// primary press is ignored, and a primary press ends a middle pan.
@MainActor
struct MiddlePanTests {
    let a = testNode(NumberTestNode.self, id: 1, at: .zero)
    let press = Vector2(600, 600)

    @Test func aMiddleDragPansTheCanvasAndNothingElse() {
        let editor = makeEditor([a])
        editor.selection = [a.id]
        editor.transform = CanvasTransform(offset: Vector2(5, 5), zoom: 2)
        editor.middleDragged(from: press, to: press)
        editor.middleDragged(from: press, to: press + Vector2(30, -20))
        guard case .panning? = editor.interaction else { Issue.record("expected a pan"); return }
        editor.middleReleased(from: press, at: press + Vector2(30, -20))
        #expect(editor.transform == CanvasTransform(offset: Vector2(35, -15), zoom: 2))
        #expect(editor.document.viewState.canvasOffset == Vector2(35, -15))
        #expect(editor.interaction == nil)
        #expect(editor.selection == [a.id] && editor.graph.nodes[a.id]?.position == .zero)
        #expect(!editor.document.canUndo, "panning is not an edit")
    }

    @Test func aMiddleDragOnANodePansAndLeavesTheNodeWhereItIs() {
        let editor = makeEditor([a])
        let onA = editor.screenPoint(in: a.id)
        editor.middleDrag(onA, onA + Vector2(0, 40))
        #expect(editor.transform.offset == Vector2(0, 40))
        #expect(editor.graph.nodes[a.id]?.position == .zero && editor.selection.isEmpty)
    }

    @Test func aMiddleClickChangesNothing() {
        let editor = makeEditor([a])
        editor.selection = [a.id]
        editor.middleDrag(press, press)
        #expect(editor.transform == CanvasTransform() && editor.selection == [a.id] && editor.interaction == nil)
    }

    /// MetalUI ignores another button's press while the primary one is held (`CI-AA` item 4); a value that arrives
    /// anyway changes nothing, and the primary drag goes on.
    @Test func aMiddleDragDuringAPrimaryPressIsIgnored() {
        let editor = makeEditor([a])
        let onA = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: onA, to: onA)
        editor.middleDrag(press, press + Vector2(40, 0))
        #expect(editor.transform == CanvasTransform() && editor.interaction == nil)
        editor.pointerDragged(from: onA, to: onA + Vector2(0, 40))
        editor.pointerReleased(from: onA, at: onA + Vector2(0, 40))
        #expect(editor.graph.nodes[a.id]?.position == Vector2(0, 40))
    }

    /// The primary button always gets its drag (MetalUI `CI-F` item 3): its press ends a middle pan under way, and the
    /// rest of that middle press is ignored, so the canvas never jumps when it moves again.
    @Test func aPrimaryPressEndsAMiddlePan() {
        let editor = makeEditor([a])
        editor.middleDragged(from: press, to: press)
        editor.middleDragged(from: press, to: press + Vector2(30, 0))
        editor.click(editor.screenPoint(in: a.id))
        #expect(editor.selection == [a.id] && editor.interaction == nil && editor.canvasCursor == nil)
        editor.middleDragged(from: press, to: press + Vector2(80, 0))
        editor.middleReleased(from: press, at: press + Vector2(80, 0))
        #expect(editor.transform.offset == Vector2(30, 0))
        editor.middleDrag(Vector2(100, 100), Vector2(110, 100))
        #expect(editor.transform.offset == Vector2(40, 0), "the next middle press pans again")
    }

    /// A middle press whose release was lost (the window resigned mid-drag) is replaced by the next one, which pans
    /// from where the canvas is.
    @Test func aMiddlePanThatLostItsReleaseIsReplacedByTheNext() {
        let editor = makeEditor([a])
        editor.middleDragged(from: press, to: press + Vector2(30, 0))
        let next = Vector2(200, 200)
        editor.middleDragged(from: next, to: next)
        editor.middleDragged(from: next, to: next + Vector2(0, 20))
        #expect(editor.transform.offset == Vector2(30, 20))
        editor.middleReleased(from: next, at: next + Vector2(0, 20))
        #expect(editor.interaction == nil)
    }
}
