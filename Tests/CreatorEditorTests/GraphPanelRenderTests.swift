import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// Headless frames of the graph panel in each state. They don't compare pixels; they prove the
/// views build, lay out and paint text and paths without trapping.
@MainActor
struct GraphPanelRenderTests {
    @Test(arguments: [DockSide.left, .bottom])
    func theGraphPanelDraws(_ dock: DockSide) {
        let editor = sampleEditor(dock: dock)
        editor.selection = [nodeID(2)]
        let input = GraphPanelInput(model: editor)
        let scene = renderHeadless { GraphPanel(model: editor, input: input) }
        #expect(!scene.glyphs.isEmpty)
        #expect(!scene.images.isEmpty)   // wires are rasterized paths
    }

    @Test func thePanelDrawsWhileDraggingAWireAndBoxSelecting() {
        let editor = sampleEditor(dock: .bottom)
        let input = GraphPanelInput(model: editor)
        let socket = editor.screenPoint(of: nodeID(1), "profile", input: false)
        editor.pointerDragged(from: socket, to: socket)
        editor.pointerDragged(from: socket, to: socket + Vector2(80, 60))
        #expect(!renderHeadless { GraphPanel(model: editor, input: input) }.isEmpty)
        editor.pointerReleased(from: socket, at: Vector2(880, 580))
        editor.modifiers = .shift
        editor.pointerDragged(from: Vector2(880, 580), to: Vector2(880, 580))
        editor.pointerDragged(from: Vector2(880, 580), to: Vector2(600, 400))
        #expect(!renderHeadless { GraphPanel(model: editor, input: input) }.isEmpty)
    }

    @Test func thePanelDrawsWithThePaletteOpenAndARefusalShowing() {
        let editor = sampleEditor(dock: .left)
        editor.pointerLocation = Vector2(200, 200)
        editor.openPalette()
        editor.connect(Link(from: Endpoint(node: nodeID(1), socket: "profile"), to: Endpoint(node: nodeID(4), socket: "radius")))
        #expect(editor.refusal != nil)
        let input = GraphPanelInput(model: editor)
        #expect(!renderHeadless { GraphPanel(model: editor, input: input) }.glyphs.isEmpty)
    }

    /// Hide must never be a one-way trip: the hidden state has a visible way back.
    @Test func theHiddenPanelLeavesAShowButton() {
        let editor = sampleEditor(dock: .hidden)
        #expect(!renderHeadless { GraphShowButton(model: editor) }.glyphs.isEmpty)
    }

    @Test func theDuplicateGhostsDraw() {
        let editor = sampleEditor(dock: .bottom)
        editor.selection = [nodeID(1)]
        editor.modifiers = .option
        let start = editor.screenPoint(in: nodeID(1))
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(0, 120))
        let input = GraphPanelInput(model: editor)
        #expect(!renderHeadless { GraphPanel(model: editor, input: input) }.isEmpty)
    }
}
