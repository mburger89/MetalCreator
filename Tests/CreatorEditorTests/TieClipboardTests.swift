import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Ties on the clipboard (cable ties spec 2026-10-26 §3.4): a tie is copied when every wire it holds is copied (both ends of
/// each in the selection), selected or not (plan ruling R7); a paste, ⌘D or ⌥-drag gives it a fresh ID, puts it on the
/// copies' wires, moves it like the nodes and selects it. Ties at a group's level (§4.5) from the editor.
@MainActor
struct TieClipboardTests {
    let scene = TieScene()

    @Test func copyingBothEndsOfEveryTiedWireCopiesTheTie() throws {
        let editor = scene.editor(ties: [scene.tie()])
        editor.selection = Set(scene.nodes.map(\.id))
        editor.copySelection()
        editor.paste()
        #expect(editor.graph.ties.count == 2)
        let copy = try #require(editor.graph.ties.values.first { $0.id != tieID(1) })
        #expect(copy.position == Vector2(408, 184), "moved like the nodes")
        let pasted = editor.canvasSelection.nodes
        #expect(copy.wires.count == 2 && copy.wires.allSatisfy { pasted.contains($0.node) }, "on the copies' wires")
        #expect(editor.canvasSelection.ties == [copy.id], "and selected with them")
        editor.perform(.undo)
        #expect(editor.graph.ties.count == 1 && editor.graph.nodes.count == 6, "one step")
    }

    @Test func aTieWithAWireLeftBehindIsNotCopied() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.selection = [scene.a1.id, scene.b1.id]
        editor.copySelection()
        editor.paste()
        #expect(editor.graph.ties.count == 1)
        #expect(editor.canvasSelection.ties.isEmpty)
    }

    @Test func duplicateAndOptionDragCopyTheTieToo() throws {
        let duplicated = scene.editor(ties: [scene.tie()])
        duplicated.selection = Set(scene.nodes.map(\.id))
        duplicated.duplicateSelection()
        #expect(duplicated.graph.ties.count == 2)
        let dragged = scene.editor(ties: [scene.tie()])
        dragged.selection = Set(scene.nodes.map(\.id))
        dragged.drag(Vector2(20, 40), Vector2(20, 640), modifiers: .option)
        let copy = try #require(dragged.graph.ties.values.first { $0.id != tieID(1) })
        #expect(copy.position == Vector2(384, 760))
    }

    @Test func cutThenPasteBringsTheTieBackOnTheCopies() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.selection = Set(scene.nodes.map(\.id))
        editor.cutSelection()
        #expect(editor.graph.ties.isEmpty, "the cut nodes took their wires out of the tie")
        editor.paste()
        #expect(editor.graph.ties.count == 1)
    }

    @Test func groupingFromTheEditorMovesTheTieInside() throws {
        let editor = scene.editor(ties: [scene.tie()])
        editor.selection = Set(scene.nodes.map(\.id))
        #expect(editor.perform(.group))
        #expect(editor.graph.ties.isEmpty)
        #expect(editor.perform(.enterGroup))
        #expect(editor.graph.ties.values.map(\.wires) == [[scene.upper, scene.lower]])
    }

    @Test func tyingInsideAGroupTiesInTheDefinition() throws {
        let editor = scene.editor()
        editor.selection = Set(scene.nodes.map(\.id))
        editor.perform(.group)
        editor.perform(.enterGroup)
        #expect(editor.isInsideGroup)
        editor.transform = CanvasTransform()
        editor.click(scene.upperMiddle)
        editor.click(scene.lowerMiddle, modifiers: .shift)
        editor.perform(.tieWires)
        #expect(editor.graph.ties.count == 1, "the level shown")
        #expect(editor.rootGraph.ties.isEmpty, "not the top level")
        #expect(editor.document.definitions.values.first?.graph.ties.count == 1)
    }
}
