import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// Add Note (⌘⇧N, the context menu) and Frame Selection (⌘⇧C, the context menu), canvas comments spec 2026-10-09 §7.
@MainActor
struct CommentCreationTests {
    let a = testNode(NumberTestNode.self, id: 1, at: Vector2(100, 100))
    let b = testNode(NumberTestNode.self, id: 2, at: Vector2(400, 200))

    func key(_ characters: String, _ modifiers: Modifiers = []) -> KeyEvent {
        KeyEvent(charactersIgnoringModifiers: characters, characters: characters, modifiers: modifiers, timestamp: 0)
    }

    @Test func addNoteMakesA160By100MutedNoteAtThePointAndSelectsItAlone() throws {
        let editor = makeEditor([a])
        editor.selection = [a.id]
        #expect(editor.addNote(atScreen: Vector2(30, 40)))
        let added = try #require(editor.graph.stickies.values.first)
        #expect(editor.graph.stickies.count == 1)
        #expect(added.text == "Note" && added.accent == .muted)
        #expect(added.frame == CanvasRect(origin: Vector2(30, 40), size: Vector2(160, 100)))
        #expect(editor.canvasSelection == CanvasSelection(comments: [added.id]))
        editor.document.undo()
        #expect(editor.graph.stickies.isEmpty && !editor.document.canUndo, "one undo step")
    }

    /// A menu item chosen while a drag is under way (a secondary press during a primary drag) would add a step in the
    /// middle of the move's coalesced run, as the keys never do (`performSelectionCommand`).
    @Test func aMenuItemChosenMidDragChangesNothingAndTheMoveStaysOneStep() {
        let editor = makeEditor([a])
        let press = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: press, to: press + Vector2(20, 0))
        guard case .moving? = editor.interaction else { Issue.record("expected a move"); return }
        #expect(!editor.isEnabled(.addNote) && !editor.isEnabled(.frameSelection), "greyed while the drag is under way")
        editor.choose(.addNote, at: Vector2(300, 300))
        editor.choose(.frameSelection, at: nil)
        #expect(editor.graph.stickies.isEmpty && editor.graph.frames.isEmpty)
        editor.pointerDragged(from: press, to: press + Vector2(40, 0))
        editor.pointerReleased(from: press, at: press + Vector2(40, 0))
        #expect(editor.graph.nodes[a.id]?.position == a.position + Vector2(40, 0))
        editor.document.undo()
        #expect(editor.graph.nodes[a.id]?.position == a.position && !editor.document.canUndo, "the whole drag, one step")
    }

    @Test func addNoteReadsTheTransformAndTheLeftDocksFlow() throws {
        let editor = makeEditor([], dock: .left)
        editor.transform = CanvasTransform(offset: Vector2(10, 20), zoom: 2)
        editor.addNote(atScreen: Vector2(110, 60))  // display canvas (50, 20)
        let added = try #require(editor.graph.stickies.values.first)
        #expect(added.frame == CanvasRect(origin: Vector2(20, 50), size: Vector2(100, 160)), "stored: the transpose")
        #expect(editor.frame(of: added) == CanvasRect(origin: Vector2(50, 20), size: Vector2(160, 100)))
    }

    @Test func theKeyPlacesTheNoteAtThePointerOrCentresItOnTheCanvas() throws {
        let editor = makeEditor([])
        editor.pointerLocation = Vector2(200, 150)
        #expect(editor.perform(.addNote))
        #expect(editor.graph.stickies.values.first?.frame.origin == Vector2(200, 150))
        let unplaced = makeEditor([])
        unplaced.transform = CanvasTransform(offset: Vector2(-100, 0), zoom: 1)
        #expect(unplaced.perform(.addNote))
        let centred = try #require(unplaced.graph.stickies.values.first)
        #expect(unplaced.transform.toScreen(centred.frame.centre) == unplaced.visibleCanvasSize * 0.5)
    }

    @Test func frameSelectionPadsTheBoundsAndAddsATitleBarAndSelectsTheFrame() throws {
        let editor = makeEditor([a, b])
        editor.selection = [a.id, b.id]
        let bounds = try #require(editor.bounds(of: editor.canvasSelection))
        #expect(editor.addFrameAroundSelection())
        let added = try #require(editor.graph.frames.values.first)
        #expect(added.title == "Frame" && added.accent == .muted)
        #expect(added.frame.origin == bounds.origin - Vector2(24, 46))
        #expect(added.frame.size == bounds.size + Vector2(48, 70))
        #expect(editor.canvasSelection == CanvasSelection(comments: [added.id]))
        #expect(editor.members(of: added) == [a.id, b.id], "the frame holds what it framed")
        editor.document.undo()
        #expect(editor.graph.frames.isEmpty && !editor.document.canUndo)
    }

    @Test func frameSelectionIsDisabledWithNothingSelected() {
        let editor = makeEditor([a])
        #expect(!editor.isEnabled(.frameSelection))
        #expect(!editor.addFrameAroundSelection())
        #expect(!editor.perform(.addFrame), "the key goes on")
        editor.canvasSelection = CanvasSelection(nodes: [nodeID(9)], comments: [commentID(9)])
        #expect(!editor.isEnabled(.frameSelection), "only items gone from the canvas")
        #expect(editor.graph.frames.isEmpty && !editor.document.canUndo)
        editor.selection = [a.id]
        #expect(editor.isEnabled(.frameSelection) && editor.isEnabled(.addNote))
    }

    @Test func frameSelectionCanFrameACommentAndWorksInTheLeftDock() throws {
        let sticky = note(1, at: Vector2(500, 100))
        let editor = makeEditor([a], stickies: [sticky], dock: .left)
        editor.canvasSelection = CanvasSelection(comments: [sticky.id])
        #expect(editor.addFrameAroundSelection())
        let added = try #require(editor.graph.frames.values.first)
        let drawn = editor.frame(of: added)
        let noteRect = editor.frame(of: sticky)
        #expect(drawn == CommentLayout.framing(noteRect))
        #expect(added.frame == editor.flow.stored(drawn))
    }

    @Test func theChordsAreCommandShiftNAndCommandShiftC() {
        func command(_ key: KeyEvent) -> GraphKeyCommand? { GraphKeyBindings.command(for: key, paletteOpen: false) }
        #expect(command(key("N", [.command, .shift])) == .addNote)
        #expect(command(key("C", [.command, .shift])) == .addFrame)
        #expect(command(key("c", .command)) == .copy, "⌘C is still copy")
        #expect(command(key("n", .command)) == nil)
        #expect(command(key("N", [.command, .shift, .option])) == nil)
        #expect(GraphKeyBindings.command(for: key("N", [.command, .shift]), paletteOpen: true) == nil)
    }

    @Test func theKeysActOnlyWhileThePanelShowsAndNotDuringADrag() {
        let hidden = makeEditor([a], dock: .hidden)
        hidden.selection = [a.id]
        #expect(!hidden.perform(.addNote) && !hidden.perform(.addFrame))
        #expect(hidden.graph.stickies.isEmpty && hidden.graph.frames.isEmpty)
        let editor = makeEditor([a])
        editor.selection = [a.id]
        let start = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(20, 0))
        #expect(editor.perform(.addNote), "claimed")
        #expect(editor.graph.stickies.isEmpty, "and does nothing, so the move stays one undo step")
    }

    @Test func theContextMenuListsTheTwoItemsAndRunsThemAtThePoint() throws {
        #expect(CanvasMenuItem.allCases.map(\.title) == ["Add Note", "Frame Selection"])
        let editor = makeEditor([a])
        editor.choose(.frameSelection, at: Vector2(5, 5))
        #expect(editor.graph.frames.isEmpty, "disabled: nothing happens")
        editor.choose(.addNote, at: Vector2(70, 80))
        let added = try #require(editor.graph.stickies.values.first)
        #expect(added.frame.origin == Vector2(70, 80))
        editor.choose(.frameSelection, at: Vector2(5, 5))
        #expect(editor.graph.frames.count == 1, "the new note is the selection, so it can be framed")
        editor.choose(.addNote, at: nil)
        #expect(editor.graph.stickies.count == 2, "a keyboard open centres the note")
    }
}
