import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// ⌘A and Esc (spec 2026-10-09 §3). Both reach the model through the window's `onInput` fallback, which a focused text
/// field pre-empts, so the field keeps its own ⌘A and Esc (human check MS-4).
@MainActor
struct SelectionKeyTests {
    let a = testNode(NumberTestNode.self, id: 1, at: .zero)
    let b = testNode(NumberTestNode.self, id: 2, at: Vector2(400, 0))

    func key(_ characters: String, _ modifiers: Modifiers = []) -> KeyEvent {
        KeyEvent(charactersIgnoringModifiers: characters, characters: characters, modifiers: modifiers, timestamp: 0)
    }

    @Test func commandAIsSelectAll() {
        #expect(GraphKeyBindings.command(for: key("a", .command), paletteOpen: false) == .selectAll)
        #expect(GraphKeyBindings.command(for: key("A", [.command, .shift]), paletteOpen: false) == nil)
        #expect(GraphKeyBindings.command(for: key("a"), paletteOpen: false) == nil)
        #expect(GraphKeyBindings.command(for: key("a", .command), paletteOpen: true) == nil, "the palette's field keeps ⌘A")
    }

    @Test func selectAllSelectsEveryNodeThroughTheInputFallback() {
        let editor = makeEditor([a, b])
        let input = GraphPanelInput(model: editor)
        #expect(input.handleKey(key("a", .command)))
        #expect(editor.selection == [a.id, b.id])
    }

    /// With the panel hidden, ⌘A would select nodes no one can see, for the next Delete to remove.
    @Test func selectAllDoesNothingWhileThePanelIsHidden() {
        let editor = makeEditor([a, b], dock: .hidden)
        #expect(!editor.perform(.selectAll))
        #expect(editor.selection.isEmpty)
    }

    /// With the panel hidden a leftover selection is out of sight, and Esc is not the editor's to claim or to clear it with.
    @Test func escapeDoesNothingWhileThePanelIsHidden() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        editor.setDock(.hidden)
        #expect(!editor.perform(.cancel), "the key goes on")
        #expect(editor.selection == [a.id])
        editor.setDock(.bottom)
        #expect(editor.perform(.cancel) && editor.selection.isEmpty)
    }

    @Test func escapeClosesThePaletteBeforeClearingTheSelection() {
        let editor = makeEditor([a])
        editor.selection = [a.id]
        editor.openPalette()
        #expect(editor.perform(.cancel))
        #expect(editor.palette == nil && editor.selection == [a.id])
        #expect(editor.perform(.cancel))
        #expect(editor.selection.isEmpty)
        #expect(!editor.perform(.cancel), "nothing left to do: the key goes on")
    }

    @Test func escapeEndsAWireDragWithoutConnectingAndKeepsTheSelection() {
        let rect = testNode(RectangleTestNode.self, id: 1, at: .zero)
        let extrude = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(300, 0))
        let editor = makeEditor([rect, extrude])
        editor.selection = [extrude.id]
        let from = editor.screenPoint(of: rect.id, "profile", input: false)
        let to = editor.screenPoint(of: extrude.id, "profile", input: true)
        editor.pointerDragged(from: from, to: from)
        editor.pointerDragged(from: from, to: to)
        guard case .connecting? = editor.interaction else { Issue.record("expected a wire drag"); return }
        #expect(editor.perform(.cancel))
        #expect(editor.interaction == nil && editor.selection == [extrude.id])
        editor.pointerDragged(from: from, to: to + Vector2(1, 0))
        #expect(editor.interaction == nil, "the rest of the press is ignored")
        editor.pointerReleased(from: from, at: to)
        #expect(editor.graph.links.isEmpty && editor.selection == [extrude.id], "no wire, and the release isn't a click")
        #expect(editor.perform(.cancel))
        #expect(editor.selection.isEmpty)
    }

    @Test func escapeDropsOptionDragGhosts() {
        let editor = makeEditor([a])
        editor.selection = [a.id]
        let start = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: start, to: start, modifiers: .option)
        editor.pointerDragged(from: start, to: start + Vector2(0, 60), modifiers: .option)
        #expect(editor.perform(.cancel))
        #expect(CanvasLayers.ghosts(editor).isEmpty)
        editor.pointerReleased(from: start, at: start + Vector2(0, 60), modifiers: .option)
        #expect(editor.graph.nodes.count == 1 && !editor.document.canUndo)
        #expect(editor.selection == [a.id])
    }

    /// A plain box replaces the selection as it grows (Task 3); Esc puts back the one it began with.
    @Test func escapePutsBackTheSelectionABoxBeganWith() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        let start = Vector2(380, -20)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: Vector2(420, 20))
        #expect(editor.selection == [b.id])
        #expect(editor.perform(.cancel))
        #expect(editor.selection == [a.id] && editor.interaction == nil)
        editor.pointerDragged(from: start, to: Vector2(430, 30))
        editor.pointerReleased(from: start, at: Vector2(430, 30))
        #expect(editor.selection == [a.id])
    }

    /// A press Esc cancelled whose release never came (the window lost key) doesn't leave the next press at the same
    /// point cancelled too: its drag box-selects as usual.
    @Test func aNewPressAfterACancelledOneWhoseReleaseWasLostDragsNormally() {
        let editor = makeEditor([a, b])
        let start = Vector2(380, -20)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: Vector2(420, 20))
        #expect(editor.perform(.cancel))
        editor.pointerPressed(at: start)
        editor.pointerDragged(from: start, to: Vector2(420, 20))
        #expect(editor.selection == [b.id], "the new press is not the cancelled one")
    }

    /// A move's steps are already in the document, so Esc doesn't cancel it; it is claimed, so it can't clear the
    /// selection mid-move (which would end the move's coalescing and split it into two undo steps).
    @Test func escapeDuringAMoveKeepsItOneUndoStep() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id, b.id]
        let start = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(0, 20))
        #expect(editor.perform(.cancel))
        #expect(editor.selection == [a.id, b.id])
        editor.pointerDragged(from: start, to: start + Vector2(0, 50))
        editor.pointerReleased(from: start, at: start + Vector2(0, 50))
        #expect(editor.graph.nodes[a.id]?.position == Vector2(0, 50))
        editor.document.undo()
        #expect(editor.graph.nodes[a.id]?.position == .zero && !editor.document.canUndo)
    }

    /// ⌘A changes the selection, whose `didSet` ends coalescing; mid-move it is claimed and does nothing, so the move
    /// stays one undo step.
    @Test func selectAllDuringAMoveKeepsItOneUndoStep() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        let start = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(0, 20))
        #expect(editor.perform(.selectAll))
        #expect(editor.selection == [a.id])
        editor.pointerDragged(from: start, to: start + Vector2(0, 50))
        editor.pointerReleased(from: start, at: start + Vector2(0, 50))
        #expect(editor.graph.nodes[a.id]?.position == Vector2(0, 50))
        editor.document.undo()
        #expect(editor.graph.nodes[a.id]?.position == .zero && !editor.document.canUndo)
    }

    /// A pan (the middle button's, Task 3) changes no document; Esc is claimed and the pan goes on.
    @Test func escapeDuringAPanIsClaimedAndThePanGoesOn() {
        let editor = makeEditor([a])
        editor.selection = [a.id]
        editor.middleDragged(from: Vector2(900, 600), to: Vector2(900, 600))
        editor.middleDragged(from: Vector2(900, 600), to: Vector2(920, 600))
        #expect(editor.perform(.cancel))
        editor.middleDragged(from: Vector2(900, 600), to: Vector2(950, 600))
        editor.middleReleased(from: Vector2(900, 600), at: Vector2(950, 600))
        #expect(editor.transform.offset == Vector2(50, 0) && editor.selection == [a.id])
    }
}
