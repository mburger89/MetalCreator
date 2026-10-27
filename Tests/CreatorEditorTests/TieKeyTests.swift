import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// ⌘⇧T (cable ties spec 2026-10-26 §4.2): with no tie selected and two or more wires, a tie holding them where they were
/// picked, selected alone ("Tie Wires"); with one tie and one or more new wires, the wires join it ("Add to Tie"); anything
/// else is refused. It acts only while the panel shows and no drag is under way.
@MainActor
struct TieKeyTests {
    let scene = TieScene()

    @Test func twoClickedWiresAreTiedAtTheCentreOfTheClicks() throws {
        let editor = scene.editor()
        editor.click(scene.upperMiddle)
        editor.click(scene.lowerMiddle, modifiers: .shift)
        #expect(editor.perform(.tieWires))
        let tie = try #require(editor.graph.ties.values.first)
        #expect(editor.graph.ties.count == 1)
        #expect(tie.wires == [scene.upper, scene.lower])
        #expect(tie.position == Vector2(384, 160))
        #expect(editor.canvasSelection == CanvasSelection(ties: [tie.id]), "the selection becomes the new tie")
        #expect(editor.document.undoName == "Tie Wires")
        editor.perform(.undo)
        #expect(editor.graph.ties.isEmpty)
    }

    @Test func boxedWiresAreTiedAtTheCentreOfWhereTheyLayInTheBox() throws {
        let editor = scene.editor()
        editor.drag(Vector2(370, 40), Vector2(400, 280), modifiers: .option)
        editor.perform(.tieWires)
        let tie = try #require(editor.graph.ties.values.first)
        #expect(tie.wires == [scene.upper, scene.lower])
        #expect(abs(tie.position.y - 160) < 1e-9 && (370...400).contains(tie.position.x))
    }

    @Test func inTheLeftDockTheTieGoesToTheStoredCentre() throws {
        let editor = scene.editor(dock: .left)
        let upper = try #require(editor.wireRouting.routes[scene.upper]?.pieces.first?.point(at: 0.5))
        let lower = try #require(editor.wireRouting.routes[scene.lower]?.pieces.first?.point(at: 0.5))
        editor.click(upper)
        editor.click(lower, modifiers: .shift)
        editor.perform(.tieWires)
        let tie = try #require(editor.graph.ties.values.first)
        #expect(tie.position == editor.flow.stored((upper + lower) * 0.5))
        #expect(tie.position == Vector2(338, 194), "the transpose of the drawn centre (194, 338)")
    }

    @Test func aTieAndAnotherWireAddTheWireToTheTie() throws {
        let editor = scene.editor(ties: [scene.tie()])
        editor.click(Vector2(384, 160))
        editor.click(scene.thirdMiddle, modifiers: .shift)
        editor.perform(.tieWires)
        let tie = try #require(editor.graph.ties[tieID(1)])
        #expect(tie.wires == [scene.upper, scene.lower, scene.third])
        #expect(tie.position == Vector2(384, 160), "adding leaves the tie where it is")
        #expect(editor.graph.ties.count == 1)
        #expect(editor.canvasSelection == CanvasSelection(ties: [tieID(1)]))
        #expect(editor.document.undoName == "Add to Tie")
    }

    @Test func anythingElseIsRefusedAndChangesNothing() {
        let selections = [
            CanvasSelection(),
            CanvasSelection(wires: [scene.upper]),
            CanvasSelection(nodes: [scene.a1.id, scene.b1.id]),
            CanvasSelection(ties: [tieID(1)]),
            CanvasSelection(wires: [scene.third], ties: [tieID(1), tieID(2)]),
            CanvasSelection(wires: [scene.upper], ties: [tieID(1)]),
        ]
        for selection in selections {
            let editor = scene.editor(ties: [scene.tie(1), scene.tie(2, at: Vector2(384, 360), holding: [scene.lower, scene.third])])
            let before = editor.graph
            editor.canvasSelection = selection
            #expect(editor.perform(.tieWires), "the key is claimed: \(selection)")
            #expect(editor.graph == before && !editor.document.canUndo, "\(selection)")
            #expect(editor.refusal?.message == EditorModel.tieRefusal, "\(selection)")
        }
    }

    @Test func itActsOnlyWhileThePanelShowsAndNothingIsDragged() {
        let hidden = scene.editor()
        hidden.canvasSelection = CanvasSelection(wires: [scene.upper, scene.lower])
        hidden.setDock(.hidden)
        #expect(!hidden.perform(.tieWires))
        #expect(hidden.graph.ties.isEmpty)
        let dragging = scene.editor()
        dragging.pointerDragged(from: Vector2(384, 380), to: Vector2(384, 380))
        dragging.pointerDragged(from: Vector2(384, 380), to: Vector2(450, 420))
        dragging.canvasSelection = CanvasSelection(wires: [scene.upper, scene.lower])
        #expect(dragging.perform(.tieWires), "claimed during a drag")
        #expect(dragging.graph.ties.isEmpty, "and does nothing")
    }
}
