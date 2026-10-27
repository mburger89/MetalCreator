import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Boxes and wires (cable ties spec 2026-10-26 §4.1): an ⌥-drag on empty canvas selects only wires, those whose taut route
/// crosses or lies inside the box, in the mode the modifiers at its start fix (⌥ replaces, ⌥⇧ adds, ⌥⌘ toggles), keeping the
/// rest of the selection, and Esc puts back what it began with. A plain box never selects wires, and picks up ties whose band
/// lies inside it. ⌘A selects ties but no wire.
@MainActor
struct WireBoxSelectTests {
    let scene = TieScene()
    let overUpper = (Vector2(370, 40), Vector2(400, 80))
    let overLower = (Vector2(370, 240), Vector2(400, 280))

    @Test func anOptionBoxSelectsTheWiresItCrossesAndKeepsTheRest() {
        let editor = scene.editor(ties: [scene.tie(at: Vector2(384, 600), holding: [scene.lower, scene.third])])
        editor.canvasSelection = CanvasSelection(nodes: [scene.a1.id], wires: [scene.third], ties: [tieID(1)])
        editor.drag(overUpper.0, overUpper.1, modifiers: .option)
        #expect(editor.canvasSelection == CanvasSelection(nodes: [scene.a1.id], wires: [scene.upper], ties: [tieID(1)]),
                "⌥ replaces the wires only")
        #expect(!editor.document.canUndo)
    }

    @Test func optionShiftAddsAndOptionCommandToggles() {
        let editor = scene.editor()
        editor.drag(overUpper.0, overUpper.1, modifiers: .option)
        editor.drag(overLower.0, overLower.1, modifiers: [.option, .shift])
        #expect(editor.canvasSelection.wires == [scene.upper, scene.lower])
        editor.drag(overUpper.0, overUpper.1, modifiers: [.option, .command])
        #expect(editor.canvasSelection.wires == [scene.lower])
        editor.drag(overLower.0, overLower.1, modifiers: [.option, .command, .shift])
        #expect(editor.canvasSelection.wires.isEmpty, "⌘ wins over ⇧")
    }

    @Test func aBoxTheWiresOnlyCrossSelectsThem() {
        let editor = scene.editor()
        editor.drag(Vector2(380, 0), Vector2(390, 300), modifiers: .option)
        #expect(editor.canvasSelection.wires == [scene.upper, scene.lower], "crossing counts, not only lying inside")
        editor.drag(Vector2(100, 500), Vector2(700, 520), modifiers: .option)
        #expect(editor.canvasSelection.wires.isEmpty, "a box over nothing replaces the wires with none")
    }

    @Test func theModeIsTheOneTheDragStartedWithAndEscPutsTheSelectionBack() {
        let editor = scene.editor()
        editor.canvasSelection = CanvasSelection(nodes: [scene.a1.id], wires: [scene.third])
        editor.pointerDragged(from: overUpper.0, to: overUpper.0, modifiers: .option)
        editor.pointerDragged(from: overUpper.0, to: overUpper.1, modifiers: .option)
        editor.pointerDragged(from: overUpper.0, to: overUpper.1 + Vector2(1, 0), modifiers: [])
        guard case .wireBoxSelecting(_, _, _, let mode)? = editor.interaction else {
            Issue.record("expected a wire box"); return
        }
        #expect(mode == .replace && editor.canvasSelection.wires == [scene.upper])
        #expect(editor.selectionBox == CanvasRect(corner: overUpper.0, overUpper.1 + Vector2(1, 0)))
        #expect(editor.perform(.cancel))
        #expect(editor.canvasSelection == CanvasSelection(nodes: [scene.a1.id], wires: [scene.third]))
        #expect(editor.interaction == nil && editor.selectionBox == nil)
        editor.pointerReleased(from: overUpper.0, at: overUpper.1, modifiers: .option)
        #expect(editor.canvasSelection == CanvasSelection(nodes: [scene.a1.id], wires: [scene.third]))
    }

    @Test func anOptionBoxRemembersWhereEachWireLayInsideIt() throws {
        let editor = scene.editor()
        editor.drag(Vector2(370, 40), Vector2(400, 280), modifiers: .option)
        let upper = try #require(editor.wirePickPoints[scene.upper]), lower = try #require(editor.wirePickPoints[scene.lower])
        #expect(abs(upper.y - 60) < 1e-9 && (370...400).contains(upper.x))
        #expect(abs(lower.y - 260) < 1e-9 && (370...400).contains(lower.x))
    }

    @Test func aPlainBoxNeverSelectsWires() {
        let editor = scene.editor()
        editor.drag(overUpper.0, overUpper.1)
        #expect(editor.canvasSelection.isEmpty)
    }

    @Test func aPlainBoxPicksUpTiesWhoseBandLiesInsideIt() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.drag(Vector2(370, 150), Vector2(400, 170))
        #expect(editor.canvasSelection == CanvasSelection(ties: [tieID(1)]))
        editor.drag(Vector2(383, 150), Vector2(400, 170))
        #expect(editor.canvasSelection.isEmpty, "a box over part of the band leaves it")
        editor.canvasSelection = CanvasSelection(ties: [tieID(1)])
        editor.drag(Vector2(370, 150), Vector2(400, 170), modifiers: .command)
        #expect(editor.canvasSelection.isEmpty, "⌘ toggles ties like nodes")
    }

    @Test func selectAllSelectsTiesButNoWire() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.selectAll()
        #expect(editor.canvasSelection == CanvasSelection(nodes: Set(scene.nodes.map(\.id)), ties: [tieID(1)]))
    }
}
