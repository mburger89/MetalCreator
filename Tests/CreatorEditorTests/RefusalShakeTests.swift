import CreatorGeometry
import CreatorGraph
import MetalUI
import Testing
@testable import CreatorEditor

/// The refusal shake (gap M5-i): the keyframes are read at injected times, the trigger is a per-node count, and a frame
/// at rest draws the node where it belongs. How it moves in a real window is human check M5-7.
@MainActor
struct RefusalShakeTests {
    let number = testNode(NumberTestNode.self, id: 4, at: Vector2(0, 300))
    let extrude = testNode(ExtrudeTestNode.self, id: 3, at: Vector2(300, 0))

    @Test(arguments: [(0.0, 0.0), (0.025, 3), (0.05, 6), (0.1, 0), (0.15, -6), (0.2, 0), (5, 0), (-1, 0)])
    func theOffsetFollowsTheKeyframes(_ time: Double, _ expected: Double) {
        #expect(abs(RefusalShake.offset(at: time) - expected) < 1e-9)
    }

    @Test func theShakeLastsAFifthOfASecondAndEndsAtRest() {
        #expect(abs(RefusalShake.duration - 0.2) < 1e-9)
        #expect(abs(RefusalShake.offset(at: RefusalShake.duration)) < 1e-9)
    }

    @Test func eachRefusalOfANodeAddsOneToItsCountAndNoOtherNode() {
        let editor = makeEditor([number, extrude])
        #expect(editor.shakeCount(of: extrude.id) == 0)
        editor.connect(wire(number, "value", extrude, "profile"))
        editor.connect(wire(number, "value", extrude, "profile"))
        #expect(editor.shakeCount(of: extrude.id) == 2)
        #expect(editor.shakeCount(of: number.id) == 0)
    }

    @Test func aCountNeverGoesDownSoClearingTheMessageDoesNotShakeAgain() {
        let editor = makeEditor([number, extrude])
        editor.connect(wire(number, "value", extrude, "profile"))
        editor.clearRefusal()
        #expect(editor.refusal == nil)
        #expect(editor.shakeCount(of: extrude.id) == 1)
    }

    /// The caption says why the last edit was refused; once another edit goes through it is stale, so it goes at once
    /// (the shake count stays: it only ever counts refusals).
    @Test func aSuccessfulEditClearsTheCaptionAtOnce() {
        let editor = makeEditor([number, extrude])
        editor.connect(wire(number, "value", extrude, "profile"))
        #expect(editor.refusal != nil)
        editor.connect(wire(number, "value", extrude, "distance"))
        #expect(editor.refusal == nil)
        #expect(editor.shakeCount(of: extrude.id) == 1)
    }

    @Test func aPasteOrAGroupEditClearsItToo() throws {
        let editor = makeEditor([number, extrude])
        editor.connect(wire(number, "value", extrude, "profile"))
        editor.selection = [number.id]
        editor.copySelection()
        editor.paste()
        #expect(editor.refusal == nil, "a paste is an edit")
        let grouped = try GroupedEditor()
        grouped.editor.renameGroup(grouped.definition.id, to: " ")
        #expect(grouped.editor.refusal?.message == "A group needs a name.")
        grouped.editor.renameGroup(grouped.definition.id, to: "Rib")
        #expect(grouped.editor.refusal == nil, "and so is a rename")
    }

    @Test func aSuccessfulGroupAndUngroupClearTheCaption() throws {
        let editor = makeEditor([number, extrude])
        editor.selection = []
        editor.groupSelection()
        #expect(editor.refusal != nil, "an empty selection is refused")
        editor.selection = [number.id, extrude.id]
        editor.groupSelection()
        #expect(editor.refusal == nil, "a group that goes through ends the old caption")
        editor.refuse("Stale.", node: nil)
        editor.ungroupSelection()
        #expect(editor.refusal == nil, "and so does an ungroup")
    }

    @Test func aParameterEditClearsTheCaption() {
        let width = GraphParameter(name: "Plate width", type: .number, value: .number(60))
        let editor = makeEditor([], parameters: [width])
        editor.refuse("Stale.", node: nil)
        editor.setParameter(width.id, to: .number(70), continuous: true)
        #expect(editor.refusal == nil)
    }

    @Test func aRefusalNamingNoNodeShakesNothing() {
        let editor = makeEditor([number])
        editor.refuse("Nothing to group.", node: nil)
        #expect(editor.refusal != nil)
        #expect(editor.shakeCounts.isEmpty)
    }

    @Test func aRefusedNodeIsDrawnAtRestWhereItBelongs() {
        let editor = makeEditor([number, extrude])
        editor.connect(wire(number, "value", extrude, "profile"))
        #expect(editor.shakeCount(of: extrude.id) == 1)
        let scene = renderHeadless { GraphPanel(model: editor, input: GraphPanelInput(model: editor)) }
        let canvas = GraphPanelLayout.canvasFrame(inPanelOf: Vector2(900, 600), flow: editor.flow, showsLibrary: editor.showsLibrary)
        let origin = canvas.origin + editor.frame(of: extrude).origin
        let painted = topRect(at: origin + Vector2(40, 60), in: scene).map { screenFrame(of: $0, in: scene) }
        #expect(painted?.origin == origin)
    }
}
