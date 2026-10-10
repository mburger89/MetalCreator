import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// Arrow keys nudge the selection 1 pt, ⇧ 10 pt, as one undo step per key-down run (spec 2026-10-09 §3).
@MainActor
struct NudgeTests {
    let a = testNode(NumberTestNode.self, id: 1, at: Vector2(100, 100))
    let b = testNode(NumberTestNode.self, id: 2, at: Vector2(400, 100))

    func key(_ characters: String, _ modifiers: Modifiers = [], isRepeat: Bool = false) -> KeyEvent {
        KeyEvent(charactersIgnoringModifiers: characters, characters: characters, modifiers: modifiers,
                 isRepeat: isRepeat, timestamp: 0)
    }

    @Test func arrowsAreNudgesOfOneOrTenPoints() {
        func command(_ key: KeyEvent) -> GraphKeyCommand? { GraphKeyBindings.command(for: key, paletteOpen: false) }
        #expect(command(key("\u{f700}")) == .nudge(Vector2(0, -1), isRepeat: false))
        #expect(command(key("\u{f701}", .shift)) == .nudge(Vector2(0, 10), isRepeat: false))
        #expect(command(key("\u{f702}", isRepeat: true)) == .nudge(Vector2(-1, 0), isRepeat: true))
        #expect(command(key("\u{f703}")) == .nudge(Vector2(1, 0), isRepeat: false))
        #expect(command(key("\u{f703}", .command)) == nil)
        #expect(command(key("\u{f703}", .option)) == nil)
        #expect(GraphKeyBindings.command(for: key("\u{f700}"), paletteOpen: true) == .paletteUp, "the palette's arrows win")
        #expect(GraphKeyBindings.command(for: key("\u{f702}"), paletteOpen: true) == nil, "← and → go to its field")
    }

    @Test func aNudgeMovesEverySelectedNode() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id, b.id]
        #expect(editor.perform(.nudge(Vector2(10, 0), isRepeat: false)))
        #expect(editor.graph.nodes[a.id]?.position == Vector2(110, 100))
        #expect(editor.graph.nodes[b.id]?.position == Vector2(410, 100))
    }

    @Test func aHeldArrowIsOneUndoStep() {
        let editor = makeEditor([a])
        editor.selection = [a.id]
        editor.perform(.nudge(Vector2(1, 0), isRepeat: false))
        for _ in 0..<3 { editor.perform(.nudge(Vector2(1, 0), isRepeat: true)) }
        #expect(editor.graph.nodes[a.id]?.position == Vector2(104, 100))
        editor.document.undo()
        #expect(editor.graph.nodes[a.id]?.position == Vector2(100, 100))
        #expect(!editor.document.canUndo)
    }

    @Test func separatePressesAreSeparateUndoSteps() {
        let editor = makeEditor([a])
        editor.selection = [a.id]
        for _ in 0..<3 { editor.perform(.nudge(Vector2(0, 1), isRepeat: false)) }
        #expect(editor.graph.nodes[a.id]?.position == Vector2(100, 103))
        editor.document.undo()
        #expect(editor.graph.nodes[a.id]?.position == Vector2(100, 102))
    }

    /// A repeat after something ended coalescing (here a selection change) starts a new step, so one step never
    /// holds two selections' moves.
    @Test func aRepeatAfterTheSelectionChangedStartsANewStep() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        editor.perform(.nudge(Vector2(1, 0), isRepeat: false))
        editor.perform(.nudge(Vector2(1, 0), isRepeat: true))
        editor.selection = [b.id]
        editor.perform(.nudge(Vector2(1, 0), isRepeat: true))
        editor.document.undo()
        #expect(editor.graph.nodes[b.id]?.position == Vector2(400, 100))
        #expect(editor.graph.nodes[a.id]?.position == Vector2(102, 100))
        editor.document.undo()
        #expect(editor.graph.nodes[a.id]?.position == Vector2(100, 100))
    }

    /// The left dock draws positions transposed; an arrow moves the node the way it points on screen.
    @Test func theLeftDockNudgesTheWayTheArrowPoints() {
        let editor = makeEditor([a], dock: .left)
        editor.selection = [a.id]
        editor.perform(.nudge(Vector2(0, 10), isRepeat: false))
        #expect(editor.graph.nodes[a.id]?.position == Vector2(110, 100))
        #expect(editor.displayOrigin(of: editor.graph.nodes[a.id] ?? a) == Vector2(100, 110))
    }

    /// A nudge ends coalescing and performs its own step; mid-move it is claimed and does nothing, so the move stays
    /// one undo step.
    @Test func aNudgeDuringAMoveKeepsItOneUndoStep() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        let start = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(0, 20))
        #expect(editor.perform(.nudge(Vector2(1, 0), isRepeat: false)), "claimed, so it doesn't reach the viewport")
        editor.pointerDragged(from: start, to: start + Vector2(0, 50))
        editor.pointerReleased(from: start, at: start + Vector2(0, 50))
        #expect(editor.graph.nodes[a.id]?.position == Vector2(100, 150))
        editor.document.undo()
        #expect(editor.graph.nodes[a.id]?.position == Vector2(100, 100) && !editor.document.canUndo)
    }

    @Test func withNothingSelectedOrThePanelHiddenTheKeyGoesOn() {
        let editor = makeEditor([a])
        #expect(!editor.perform(.nudge(Vector2(1, 0), isRepeat: false)))
        editor.selection = [nodeID(9)]
        #expect(!editor.perform(.nudge(Vector2(1, 0), isRepeat: false)), "a stale selection moves nothing")
        let hidden = makeEditor([a], dock: .hidden)
        hidden.selection = [a.id]
        #expect(!hidden.perform(.nudge(Vector2(1, 0), isRepeat: false)))
        #expect(hidden.graph.nodes[a.id]?.position == Vector2(100, 100) && !hidden.document.canUndo)
    }

    @Test func arrowsReachTheModelThroughTheInputFallback() {
        let editor = makeEditor([a])
        editor.selection = [a.id]
        let input = GraphPanelInput(model: editor)
        #expect(input.handleKey(key("\u{f703}", .shift)))
        #expect(editor.graph.nodes[a.id]?.position == Vector2(110, 100))
    }
}
