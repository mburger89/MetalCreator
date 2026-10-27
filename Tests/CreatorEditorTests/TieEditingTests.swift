import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Editing ties (cable ties spec 2026-10-26 §4.3, §4.4). A drag or an arrow moves a tie as one undo step ("Move Tie", "Move"
/// with other items). Delete removes selected ties ("Remove Tie") and does nothing with only wires selected. ⌥-click on a
/// wire's lane unties it ("Untie Wire"), (I2) applying. Deleting a node or a wire takes its wires out of their ties, and
/// everything undoes.
@MainActor
struct TieEditingTests {
    let scene = TieScene()

    @Test func draggingATieMovesItAsOneUndoStep() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.pointerDragged(from: Vector2(384, 160), to: Vector2(384, 160))
        editor.pointerDragged(from: Vector2(384, 160), to: Vector2(404, 180))
        editor.pointerDragged(from: Vector2(384, 160), to: Vector2(434, 200))
        editor.pointerReleased(from: Vector2(384, 160), at: Vector2(434, 200))
        #expect(editor.graph.ties[tieID(1)]?.position == Vector2(434, 200))
        #expect(editor.canvasSelection == CanvasSelection(ties: [tieID(1)]))
        #expect(editor.document.undoName == "Move Tie")
        editor.perform(.undo)
        #expect(editor.graph.ties[tieID(1)]?.position == Vector2(384, 160), "one step")
    }

    @Test func aTieMovesTogetherWithSelectedNodes() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.canvasSelection = CanvasSelection(nodes: [scene.a1.id], ties: [tieID(1)])
        editor.drag(Vector2(20, 40), Vector2(50, 50))
        #expect(editor.graph.nodes[scene.a1.id]?.position == Vector2(30, 10))
        #expect(editor.graph.ties[tieID(1)]?.position == Vector2(414, 170))
        #expect(editor.document.undoName == "Move")
        editor.perform(.undo)
        #expect(editor.graph.nodes[scene.a1.id]?.position == .zero && editor.graph.ties[tieID(1)]?.position == Vector2(384, 160))
    }

    @Test func aTieDraggedInTheLeftDockMovesInStoredCoordinates() {
        let editor = scene.editor(ties: [scene.tie()], dock: .left)
        editor.drag(Vector2(160, 384), Vector2(160, 434))
        #expect(editor.graph.ties[tieID(1)]?.position == Vector2(434, 160))
    }

    @Test func anArrowNudgesASelectedTie() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.canvasSelection = CanvasSelection(ties: [tieID(1)])
        #expect(editor.perform(.nudge(Vector2(10, 0), isRepeat: false)))
        #expect(editor.graph.ties[tieID(1)]?.position == Vector2(394, 160))
        #expect(editor.document.undoName == "Move Tie")
    }

    @Test func deleteRemovesSelectedTiesAndLeavesTheirWires() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.canvasSelection = CanvasSelection(ties: [tieID(1)])
        editor.perform(.deleteSelection)
        #expect(editor.graph.ties.isEmpty && editor.graph.links.count == 3)
        #expect(editor.canvasSelection.isEmpty)
        #expect(editor.document.undoName == "Remove Tie")
        editor.perform(.undo)
        #expect(editor.graph.ties[tieID(1)] == scene.tie())
    }

    @Test func deleteWithOnlyWiresSelectedDoesNothing() {
        let editor = scene.editor()
        editor.canvasSelection = CanvasSelection(wires: [scene.upper, scene.lower])
        editor.perform(.deleteSelection)
        #expect(editor.graph.links.count == 3 && !editor.document.canUndo && editor.refusal == nil)
    }

    @Test func deletingANodeTakesItsWiresOutOfTheirTies() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.selection = [scene.b1.id]
        editor.perform(.deleteSelection)
        #expect(editor.graph.ties.isEmpty, "upper left, and one wire is no tie")
        #expect(editor.document.undoName == "Delete")
        editor.perform(.undo)
        #expect(editor.graph.ties[tieID(1)] == scene.tie())
    }

    @Test func deletingANodeAndItsTieTogetherIsOneStep() {
        let editor = scene.editor(ties: [scene.tie()])
        let before = editor.graph
        editor.canvasSelection = CanvasSelection(nodes: [scene.b1.id], ties: [tieID(1)])
        editor.perform(.deleteSelection)
        #expect(editor.graph.ties.isEmpty && editor.graph.nodes[scene.b1.id] == nil && editor.refusal == nil)
        #expect(editor.document.undoName == "Delete")
        editor.perform(.undo)
        #expect(editor.graph == before)
    }

    @Test func draggingAWiredInputOffUntiesItsWire() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.drag(Vector2(600, 60), Vector2(900, 600))
        #expect(editor.graph.incomingLink(to: scene.upper) == nil)
        #expect(editor.graph.ties.isEmpty)
        editor.perform(.undo)
        #expect(editor.graph.ties[tieID(1)] == scene.tie())
    }

    /// Three wires at (384, 160): lanes `upper` 156, `lower` 160, `third` 164. Once `upper` leaves, two are left, on lanes
    /// 158 and 162.
    @Test func anOptionClickOnALaneUntiesThatWire() {
        let editor = scene.editor(ties: [scene.tie(holding: [scene.upper, scene.lower, scene.third])])
        editor.click(Vector2(384, 156), modifiers: .option)
        #expect(editor.graph.ties[tieID(1)]?.wires == [scene.lower, scene.third])
        #expect(editor.document.undoName == "Untie Wire")
        editor.click(Vector2(384, 158), modifiers: .option)
        #expect(editor.graph.ties.isEmpty, "untying one of two removes the tie (I2)")
        #expect(!editor.canvasSelection.ties.contains(tieID(1)))
        editor.perform(.undo)
        editor.perform(.undo)
        #expect(editor.graph.ties[tieID(1)]?.wires == [scene.upper, scene.lower, scene.third])
    }

    @Test func anOptionClickOnAPlainWireSelectsIt() {
        let editor = scene.editor(ties: [scene.tie(at: Vector2(384, 600))])
        editor.click(scene.thirdMiddle, modifiers: .option)
        #expect(editor.canvasSelection == CanvasSelection(wires: [scene.third]))
        #expect(!editor.document.canUndo)
    }

    @Test func aGoneTieOrWireInTheSelectionIsSkipped() {
        let editor = scene.editor()
        editor.canvasSelection = CanvasSelection(wires: [scene.upper, scene.lower])
        editor.perform(.tieWires)
        editor.perform(.undo)
        #expect(editor.graph.ties.isEmpty && editor.canvasSelection.ties.count == 1, "set up: the selection names a gone tie")
        editor.perform(.deleteSelection)
        #expect(!editor.document.canUndo && editor.refusal == nil, "Delete skips it without a step")
        #expect(!editor.perform(.nudge(Vector2(1, 0), isRepeat: false)), "nothing to nudge")
        editor.canvasSelection.wires = [scene.upper]
        editor.perform(.tieWires)
        #expect(editor.graph.ties.isEmpty && editor.refusal?.message == EditorModel.tieRefusal)
        editor.drag(Vector2(384, 160), Vector2(434, 200))
        #expect(!editor.document.canUndo, "the drag where the tie was is a box")
    }
}
