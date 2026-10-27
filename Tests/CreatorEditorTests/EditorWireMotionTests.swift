import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Testing
@testable import CreatorEditor

/// Slack in the editor (cable ties spec 2026-10-26 §5.2). Moving a node or a tie makes the wires it moves go slack, against the
/// motion; the canvas animates only while some wire is slack and stops once every wire is taut. Undo and a click make no
/// slack. With Reduce Motion on, no slack is ever made.
@MainActor
struct EditorWireMotionTests {
    let scene = TieScene()

    func editor(ties: [CableTie] = []) -> (EditorModel, ManualClock) {
        let clock = ManualClock()
        let editor = scene.editor(ties: ties)
        editor.motionClock = { clock.now }
        return (editor, clock)
    }

    @Test func draggingANodeMakesItsWiresSlackAgainstTheMotion() throws {
        let (editor, _) = editor()
        editor.drag(Vector2(700, 50), Vector2(700, 90))
        #expect(editor.isWireMotionActive)
        let spring = try #require(editor.wireMotion.springs[scene.upper]?.first)
        #expect(spring.control2.offset.y < 0 && spring.control2.offset.x == 0, "b1 moved down: its end bows up")
        #expect(spring.control1 == SpringPoint())
        #expect(editor.wireMotion.springs[scene.lower] == nil, "a wire nothing moved stays taut")
    }

    @Test func draggingATieMakesBothSidesOfItsWiresSlack() {
        let (editor, _) = editor(ties: [scene.tie()])
        editor.drag(Vector2(384, 160), Vector2(384, 200))
        #expect(editor.wireMotion.springs[scene.upper]?.count == 2)
        #expect(editor.wireMotion.springs[scene.lower]?.count == 2)
    }

    @Test func theWiresSettleAndTheTimelineStops() {
        let (editor, clock) = editor()
        editor.drag(Vector2(700, 50), Vector2(700, 90))
        #expect(CanvasLayers.animatesWires(editor, reducesMotion: false))
        clock.now += 0.1
        editor.settleWireMotion()
        #expect(editor.isWireMotionActive, "still slack a tenth of a second on")
        clock.now += 1
        editor.settleWireMotion()
        #expect(!editor.isWireMotionActive && editor.wireMotion.isAtRest)
        #expect(!CanvasLayers.animatesWires(editor, reducesMotion: false), "at rest the wires draw without a timeline")
    }

    @Test func whileSlackTheDrawnWiresKeepTheirEndsAndBow() throws {
        let (editor, clock) = editor()
        editor.drag(Vector2(700, 50), Vector2(700, 90))
        let taut = try #require(editor.wireRouting.routes[scene.upper])
        let motion = editor.drawnMotion(at: Date(timeIntervalSinceReferenceDate: clock.now + 0.05))
        let drawn = try #require(CanvasLayers.wires(editor, motion: motion).first { $0.route.wire == scene.upper })
        #expect(drawn.route.pinned == taut.pinned, "the ends are exact")
        #expect(drawn.route != taut, "the control points carry the slack")
        let middle = try #require(taut.pieces.first?.point(at: 0.5))
        #expect(editor.hitTest(editor.transform.toScreen(middle)) == .wire(scene.upper), "hit testing reads the taut route")
    }

    @Test func undoAndAClickMakeNoSlack() {
        let (editor, clock) = editor()
        editor.drag(Vector2(700, 50), Vector2(700, 90))
        clock.now += 2
        editor.settleWireMotion()
        editor.perform(.undo)
        #expect(editor.wireMotion.isAtRest && !editor.isWireMotionActive)
        editor.click(Vector2(700, 50))
        #expect(editor.wireMotion.isAtRest)
    }

    @Test func undoMidMotionSnapsTheWiresTaut() {
        let (editor, _) = editor()
        editor.drag(Vector2(700, 50), Vector2(700, 90))
        #expect(editor.isWireMotionActive)
        editor.perform(.undo)
        #expect(editor.wireMotion.isAtRest && !editor.isWireMotionActive, "plan R13: no spring survives an undo")
    }

    @Test func aDockChangeMidMotionSnapsTheWiresTaut() {
        let (editor, _) = editor()
        editor.drag(Vector2(700, 50), Vector2(700, 90))
        #expect(editor.isWireMotionActive)
        editor.setDock(editor.dock == .bottom ? .left : .bottom)
        #expect(editor.wireMotion.isAtRest && !editor.isWireMotionActive)
    }

    @Test func aPasteMidMotionSnapsTheWiresTaut() {
        let (editor, _) = editor()
        editor.selection = [scene.b1.id]
        editor.copySelection()
        editor.drag(Vector2(700, 50), Vector2(700, 90))
        #expect(editor.isWireMotionActive)
        editor.paste()
        #expect(editor.wireMotion.isAtRest && !editor.isWireMotionActive)
    }

    @Test func anArrowNudgeMakesSlackToo() {
        let (editor, _) = editor()
        editor.selection = [scene.b1.id]
        editor.perform(.nudge(Vector2(0, 10), isRepeat: false))
        #expect(editor.wireMotion.springs[scene.upper] != nil)
    }

    @Test func withReduceMotionOnNoSlackIsEverMade() {
        let (editor, _) = editor()
        editor.reducesMotion = true
        editor.drag(Vector2(700, 50), Vector2(700, 90))
        #expect(editor.wireMotion.isAtRest && !editor.isWireMotionActive)
        #expect(!CanvasLayers.animatesWires(editor, reducesMotion: true))
    }

    @Test func turningReduceMotionOnMidMotionMakesTheWiresTaut() {
        let (editor, _) = editor()
        editor.drag(Vector2(700, 50), Vector2(700, 90))
        #expect(editor.isWireMotionActive)
        editor.reducesMotion = true
        #expect(editor.wireMotion.isAtRest && !editor.isWireMotionActive)
    }

    @Test func aCanvasInMotionStillDraws() {
        let (editor, _) = editor(ties: [scene.tie()])
        editor.drag(Vector2(384, 160), Vector2(384, 200))
        let frame = renderHeadless { GraphPanel(model: editor, input: GraphPanelInput(model: editor)) }
        #expect(!frame.rects.isEmpty)
    }
}
