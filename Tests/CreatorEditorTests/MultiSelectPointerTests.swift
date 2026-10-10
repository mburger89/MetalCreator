import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Clicks and drags on nodes with ⌘, ⇧ and ⌥ (spec 2026-10-09 §3): ⌘-click toggles, ⇧ keeps adding, no modifier
/// replaces; a press on a selected node without movement collapses the selection to it (⌘: toggles it), so a ⌘-drag
/// still moves the selection; ⌥-drag copies the whole selection once the pointer moves.
@MainActor
struct MultiSelectPointerTests {
    let a = testNode(NumberTestNode.self, id: 1, at: .zero)
    let b = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0))
    let c = testNode(NumberTestNode.self, id: 3, at: Vector2(600, 0))

    @Test func commandClickTogglesANodeInAndOut() {
        let editor = makeEditor([a, b, c])
        editor.selection = [a.id]
        editor.click(editor.screenPoint(in: b.id), modifiers: .command)
        #expect(editor.selection == [a.id, b.id])
        editor.click(editor.screenPoint(in: a.id), modifiers: .command)
        #expect(editor.selection == [b.id])
        editor.click(editor.screenPoint(in: b.id), modifiers: [.command, .shift])
        #expect(editor.selection.isEmpty, "⌘ wins over ⇧")
    }

    @Test func shiftClickKeepsAdding() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        editor.click(editor.screenPoint(in: b.id), modifiers: .shift)
        #expect(editor.selection == [a.id, b.id])
        editor.click(editor.screenPoint(in: a.id), modifiers: .shift)
        #expect(editor.selection == [a.id, b.id], "⇧ never removes")
    }

    @Test func aPlainClickOnASelectedNodeCollapsesTheSelectionToIt() {
        let editor = makeEditor([a, b, c])
        editor.selection = [a.id, b.id, c.id]
        editor.click(editor.screenPoint(in: b.id))
        #expect(editor.selection == [b.id])
    }

    @Test func aModifiedClickOnEmptyCanvasKeepsTheSelection() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id, b.id]
        editor.click(Vector2(900, 600), modifiers: .command)
        editor.click(Vector2(900, 600), modifiers: .shift)
        #expect(editor.selection == [a.id, b.id])
        editor.click(Vector2(900, 600))
        #expect(editor.selection.isEmpty)
    }

    @Test func aSocketClickSelectsItsNodeByTheSameModes() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        editor.click(editor.screenPoint(of: b.id, "value", input: true), modifiers: .command)
        #expect(editor.selection == [a.id, b.id])
    }

    @Test func commandDragMovesTheSelectionAndKeepsIt() {
        let editor = makeEditor([a, b, c])
        editor.selection = [a.id, b.id]
        let start = editor.screenPoint(in: a.id)
        editor.drag(start, start + Vector2(0, 40), modifiers: .command)
        #expect(editor.selection == [a.id, b.id], "a ⌘-drag doesn't toggle the node it began on")
        #expect(editor.graph.nodes[a.id]?.position == Vector2(0, 40))
        #expect(editor.graph.nodes[b.id]?.position == Vector2(300, 40))
        #expect(editor.graph.nodes[c.id]?.position == Vector2(600, 0))
        editor.document.undo()
        #expect(editor.graph.nodes[a.id]?.position == .zero && editor.graph.nodes[b.id]?.position == Vector2(300, 0))
        #expect(!editor.document.canUndo, "one undo step")
    }

    @Test func aModifiedDragOnAnUnselectedNodeAddsItAndMovesEverything() {
        for modifiers: CanvasModifiers in [.shift, .command] {
            let editor = makeEditor([a, b, c])
            editor.selection = [a.id]
            let start = editor.screenPoint(in: b.id)
            editor.drag(start, start + Vector2(0, 40), modifiers: modifiers)
            #expect(editor.selection == [a.id, b.id])
            #expect(editor.graph.nodes[a.id]?.position == Vector2(0, 40))
            #expect(editor.graph.nodes[b.id]?.position == Vector2(300, 40))
            #expect(editor.graph.nodes[c.id]?.position == Vector2(600, 0))
        }
    }

    @Test func optionDragCopiesTheWholeSelectionOnlyOnceItMoves() {
        let editor = makeEditor([a, b, c])
        editor.selection = [a.id, b.id]
        let start = editor.screenPoint(in: b.id)
        editor.pointerDragged(from: start, to: start, modifiers: .option)
        editor.pointerDragged(from: start, to: start + Vector2(2, 0), modifiers: .option)
        #expect(editor.interaction == nil && CanvasLayers.ghosts(editor).isEmpty, "not yet a drag: nothing is copied")
        editor.pointerDragged(from: start, to: start + Vector2(0, 60), modifiers: .option)
        #expect(CanvasLayers.ghosts(editor).map(\.position) == [Vector2(0, 60), Vector2(300, 60)])
        editor.pointerReleased(from: start, at: start + Vector2(0, 60), modifiers: .option)
        #expect(editor.graph.nodes.count == 5)
        #expect(editor.selection.count == 2 && editor.selection.isDisjoint(with: [a.id, b.id, c.id]))
        #expect(Set(editor.selection.compactMap { editor.graph.nodes[$0]?.position }) == [Vector2(0, 60), Vector2(300, 60)])
        editor.document.undo()
        #expect(editor.graph.nodes.count == 3 && !editor.document.canUndo)
    }
}
