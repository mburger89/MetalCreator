import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// The panel's geometry is computed (`GraphPanelLayout`), and the host says where the panel is in its window
/// (`EditorModel.placement`), so the editor knows where its canvas is without measuring anything (gap M4-a).
@MainActor
struct PanelPlacementTests {
    @Test func theCanvasSitsUnderTheHeaderInsideTheGlass() {
        let frame = GraphPanelLayout.canvasFrame(inPanelOf: Vector2(400, 300))
        #expect(frame.origin == Vector2(10, 46))
        #expect(frame.size == Vector2(380, 244))
        #expect(GraphPanelLayout.canvasFrame(inPanelOf: Vector2(10, 10)).size == .zero, "never negative")
    }

    @Test func theHostPlacesTheCanvasInTheWindow() {
        let editor = makeEditor([], dock: .bottom)
        #expect(editor.canvasFrameInWindow == nil, "no host, no window coordinates")
        let panel = CanvasRect(origin: Vector2(12, 388), size: Vector2(976, 300))
        editor.placement = { PanelPlacement(window: Vector2(1000, 700), panel: panel) }
        #expect(editor.canvasFrameInWindow == CanvasRect(origin: Vector2(22, 434), size: Vector2(956, 244)))
        #expect(editor.windowPoint(fromCanvas: Vector2(5, 6)) == Vector2(27, 440))
        editor.setDock(.hidden)
        #expect(editor.canvasFrameInWindow == nil, "a hidden panel has no canvas")
    }

    /// The header is framed to `GraphPanelLayout.headerHeight`, so the canvas starts where the layout says: a node
    /// at the canvas origin, unpanned and unzoomed, is drawn at `canvasFrame`'s origin.
    @Test(arguments: [DockSide.left, .bottom])
    func aNodeAtTheCanvasOriginIsDrawnWhereTheLayoutPutsTheCanvas(_ dock: DockSide) {
        let editor = makeEditor([testNode(NumberTestNode.self, id: 1, at: .zero)], dock: dock)
        let input = GraphPanelInput(model: editor)
        let scene = renderHeadless { GraphPanel(model: editor, input: input) }
        let scale = 2.0
        let origin = GraphPanelLayout.canvasFrame(inPanelOf: Vector2(900, 600)).origin
        let body = scene.rects.contains { rect in
            abs(Double(rect.bounds.origin.x) / scale - origin.x) < 0.5
                && abs(Double(rect.bounds.origin.y) / scale - origin.y) < 0.5
                && abs(Double(rect.bounds.size.width) / scale - NodeLayout.width) < 0.5
        }
        #expect(body, "no node drawn at \(origin)")
    }
}
