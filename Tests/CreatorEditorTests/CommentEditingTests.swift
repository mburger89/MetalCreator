import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// Comments join delete, cut, copy, paste and duplicate (canvas comments spec 2026-10-09 §7), each one undo step; a
/// deleted frame keeps its nodes.
@MainActor
struct CommentEditingTests {
    let a = testNode(NumberTestNode.self, id: 1, at: Vector2(100, 100))
    let b = testNode(NumberTestNode.self, id: 2, at: Vector2(700, 100))
    var sticky = note(1, "Remember", at: Vector2(300, 0))
    var frame = box(2, "Bracket", at: Vector2(50, 50), size: Vector2(300, 200))

    init() {
        sticky.accent = .pink
        frame.accent = .cyan
    }

    func editor() -> EditorModel { makeEditor([a, b], stickies: [sticky], frames: [frame]) }

    @Test func deleteTakesTheSelectedCommentsWithTheNodesAsOneStepAndUndoPutsThemBack() {
        let editor = editor()
        let before = editor.graph
        editor.canvasSelection = CanvasSelection(nodes: [b.id], comments: [sticky.id, frame.id])
        editor.deleteSelection()
        #expect(editor.graph.nodes.keys.contains(b.id) == false)
        #expect(editor.graph.commentIDs.isEmpty)
        #expect(editor.canvasSelection.isEmpty)
        editor.document.undo()
        #expect(editor.graph == before)
        #expect(!editor.document.canUndo)
    }

    @Test func deletingAFrameKeepsTheNodesItHeld() {
        let editor = editor()
        #expect(editor.members(of: frame) == [a.id])
        editor.canvasSelection = CanvasSelection(comments: [frame.id])
        editor.deleteSelection()
        #expect(editor.graph.frames.isEmpty)
        #expect(editor.graph.nodes[a.id]?.position == Vector2(100, 100))
    }

    @Test func deleteAcceptsACommentOnlySelectionAndIgnoresAGoneOne() {
        let editor = editor()
        editor.canvasSelection = CanvasSelection(comments: [commentID(9)])
        editor.deleteSelection()
        #expect(!editor.document.canUndo, "nothing to delete")
        #expect(editor.perform(.deleteSelection), "the key is used while anything is selected")
        editor.canvasSelection = CanvasSelection(comments: [sticky.id])
        #expect(editor.perform(.deleteSelection))
        #expect(editor.graph.stickies.isEmpty)
    }

    @Test func copyAndPasteMakeFreshCommentsOffsetFurtherEachTimeAndSelectThem() throws {
        let editor = editor()
        editor.canvasSelection = CanvasSelection(nodes: [a.id], comments: [sticky.id, frame.id])
        editor.copySelection()
        editor.paste()
        let first = editor.canvasSelection
        #expect(first.nodes.count == 1 && first.comments.count == 2)
        #expect(first.comments.isDisjoint(with: [sticky.id, frame.id]))
        let copiedNote = try #require(first.comments.compactMap { editor.graph.stickies[$0] }.first)
        #expect(copiedNote.text == "Remember" && copiedNote.accent == .pink)
        #expect(copiedNote.frame == CanvasRect(origin: Vector2(324, 24), size: Vector2(160, 100)))
        let copiedFrame = try #require(first.comments.compactMap { editor.graph.frames[$0] }.first)
        #expect(copiedFrame.title == "Bracket" && copiedFrame.accent == .cyan)
        #expect(copiedFrame.frame.origin == Vector2(74, 74))
        editor.paste()
        let second = editor.canvasSelection.comments.compactMap { editor.graph.stickies[$0] }.first
        #expect(second?.frame.origin == Vector2(348, 48))
        editor.document.undo()
        editor.document.undo()
        #expect(editor.graph.stickies.count == 1 && editor.graph.frames.count == 1 && !editor.document.canUndo)
    }

    /// A copy of a frame together with the nodes it held puts the copies in the copied frame, since both move by the
    /// same offset: membership is geometric and so survives the copy.
    @Test func aCopiedFrameHoldsTheCopiedNodesItWasCopiedWith() throws {
        let editor = editor()
        editor.canvasSelection = CanvasSelection(nodes: [a.id], comments: [frame.id])
        let copies = try #require(editor.insert(editor.clipboard(of: editor.canvasSelection), offset: Vector2(0, 500),
                                                named: UndoName.paste))
        let copiedFrame = try #require(copies.comments.compactMap { editor.graph.frames[$0] }.first)
        #expect(copies.nodes.count == 1 && editor.members(of: copiedFrame) == copies.nodes)
        #expect(editor.members(of: frame) == [a.id], "and the original still holds the original")
    }

    @Test func aCommentOnlyCopyPastes() {
        let editor = editor()
        editor.canvasSelection = CanvasSelection(comments: [sticky.id])
        editor.copySelection()
        #expect(editor.clipboard?.stickies == [sticky] && editor.clipboard?.nodes.isEmpty == true)
        editor.paste()
        #expect(editor.graph.stickies.count == 2)
        #expect(editor.canvasSelection.nodes.isEmpty && editor.canvasSelection.comments.count == 1)
    }

    @Test func duplicateLeavesTheClipboardAloneAndCopiesAFrameWithoutItsNodes() {
        let editor = editor()
        editor.canvasSelection = CanvasSelection(comments: [frame.id])
        editor.duplicateSelection()
        #expect(editor.clipboard == nil)
        #expect(editor.graph.frames.count == 2 && editor.graph.nodes.count == 2, "the frame's node isn't copied")
        #expect(editor.canvasSelection.comments.count == 1 && editor.canvasSelection.comments.isDisjoint(with: [frame.id]))
        editor.document.undo()
        #expect(editor.graph.frames.count == 1 && !editor.document.canUndo)
    }

    @Test func cutCopiesThenDeletesAsOneStepAndPasteBringsItBack() {
        let editor = editor()
        editor.canvasSelection = CanvasSelection(nodes: [a.id], comments: [sticky.id])
        #expect(editor.perform(.cut))
        #expect(editor.graph.nodes.keys.contains(a.id) == false && editor.graph.stickies.isEmpty)
        #expect(editor.clipboard?.nodes.map(\.id) == [a.id] && editor.clipboard?.stickies == [sticky])
        editor.paste()
        #expect(editor.graph.nodes.count == 2 && editor.graph.stickies.count == 1)
        editor.document.undo()
        editor.document.undo()
        #expect(editor.graph.nodes.count == 2 && editor.graph.stickies == [sticky.id: sticky], "cut was one step")
        #expect(!editor.document.canUndo)
        let empty = makeEditor([a])
        #expect(!empty.perform(.cut), "nothing selected: the key goes on")
    }

    @Test func commandXIsCut() {
        func key(_ characters: String, _ modifiers: Modifiers = []) -> KeyEvent {
            KeyEvent(charactersIgnoringModifiers: characters, characters: characters, modifiers: modifiers, timestamp: 0)
        }
        #expect(GraphKeyBindings.command(for: key("x", .command), paletteOpen: false) == .cut)
        #expect(GraphKeyBindings.command(for: key("x"), paletteOpen: false) == nil)
        #expect(GraphKeyBindings.command(for: key("x", .command), paletteOpen: true) == nil)
    }
}
