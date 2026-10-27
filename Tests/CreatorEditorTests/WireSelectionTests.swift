import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Clicking wires and ties (cable ties spec 2026-10-26 §4.1): a click selects, replacing the selection; ⇧ adds, ⌘ toggles,
/// ⌘ wins; a click on empty canvas clears everything. View state, never undone. A click on a wire remembers where it
/// landed, in stored coordinates, for ⌘⇧T.
@MainActor
struct WireSelectionTests {
    let scene = TieScene()

    @Test func aClickOnAWireSelectsItAlone() {
        let editor = scene.editor()
        editor.selection = [scene.a1.id]
        editor.click(scene.upperMiddle)
        #expect(editor.canvasSelection == CanvasSelection(wires: [scene.upper]))
        #expect(!editor.document.canUndo)
    }

    @Test func shiftAddsCommandTogglesAndCommandWins() {
        let editor = scene.editor()
        editor.click(scene.upperMiddle)
        editor.click(scene.lowerMiddle, modifiers: .shift)
        #expect(editor.canvasSelection.wires == [scene.upper, scene.lower])
        editor.click(scene.upperMiddle, modifiers: .command)
        #expect(editor.canvasSelection.wires == [scene.lower])
        editor.click(scene.lowerMiddle, modifiers: [.command, .shift])
        #expect(editor.canvasSelection.wires.isEmpty)
    }

    @Test func aClickOnATieSelectsItAndShiftAddsAWire() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.click(Vector2(384, 160))
        #expect(editor.canvasSelection == CanvasSelection(ties: [tieID(1)]))
        editor.click(scene.thirdMiddle, modifiers: .shift)
        #expect(editor.canvasSelection == CanvasSelection(wires: [scene.third], ties: [tieID(1)]))
    }

    @Test func aClickOnEmptyCanvasClearsWiresAndTiesToo() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.canvasSelection = CanvasSelection(nodes: [scene.a1.id], wires: [scene.upper], ties: [tieID(1)])
        editor.click(Vector2(384, 380))
        #expect(editor.canvasSelection.isEmpty)
    }

    @Test func aClickRemembersWhereItPickedTheWire() {
        let editor = scene.editor()
        editor.click(scene.upperMiddle + Vector2(10, 2))
        #expect(editor.wirePickPoints[scene.upper] == Vector2(394, 62))
        let left = scene.editor(dock: .left)
        left.click(Vector2(94, 338))
        #expect(left.wirePickPoints[scene.upper] == Vector2(338, 94), "stored, so the transpose of the drawn point")
    }
}
