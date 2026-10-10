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
    @Test func theBodySitsUnderTheHeaderInsideTheGlass() {
        let body = GraphPanelLayout.bodyFrame(inPanelOf: Vector2(400, 300))
        #expect(body.origin == Vector2(10, 46))
        #expect(body.size == Vector2(380, 244))
        #expect(GraphPanelLayout.bodyFrame(inPanelOf: Vector2(10, 10)).size == .zero, "never negative")
        #expect(GraphPanelLayout.canvasFrame(inPanelOf: Vector2(400, 300), flow: .horizontal, showsLibrary: false) == body)
    }

    /// Docked at the bottom (horizontal flow) the library is a column at the canvas's left edge; docked left
    /// (vertical flow) a strip across its top.
    @Test func theLibrarySitsOnTheSideTheGraphFlowsFrom() {
        let size = Vector2(800, 300)
        #expect(GraphPanelLayout.libraryFrame(inPanelOf: size, flow: .horizontal)
                == CanvasRect(origin: Vector2(10, 46), size: Vector2(176, 244)))
        #expect(GraphPanelLayout.canvasFrame(inPanelOf: size, flow: .horizontal, showsLibrary: true)
                == CanvasRect(origin: Vector2(194, 46), size: Vector2(596, 244)))
        let tall = Vector2(400, 700)
        #expect(GraphPanelLayout.libraryFrame(inPanelOf: tall, flow: .vertical)
                == CanvasRect(origin: Vector2(10, 46), size: Vector2(380, 176)))
        #expect(GraphPanelLayout.canvasFrame(inPanelOf: tall, flow: .vertical, showsLibrary: true)
                == CanvasRect(origin: Vector2(10, 230), size: Vector2(380, 460)))
    }

    /// A refusal message showing under the body takes one caption line and the spacing above it from the body's bottom,
    /// so the editor's idea of where the canvas is matches what `GraphPanel` lays out.
    @Test func aRefusalLineTakesOneCaptionLineFromTheBodysBottom() {
        let line = Vector2(0, GraphPanelLayout.refusalLineHeight + GraphPanelLayout.spacing)
        let size = Vector2(800, 300)
        let body = GraphPanelLayout.bodyFrame(inPanelOf: size)
        let shown = GraphPanelLayout.bodyFrame(inPanelOf: size, showsRefusal: true)
        #expect(shown.origin == body.origin && shown.size == body.size - line)
        #expect(GraphPanelLayout.bodyFrame(inPanelOf: Vector2(10, 10), showsRefusal: true).size == .zero, "never negative")
        for (flow, library) in [(CanvasFlow.horizontal, false), (.horizontal, true), (.vertical, false), (.vertical, true)] {
            let plain = GraphPanelLayout.canvasFrame(inPanelOf: size, flow: flow, showsLibrary: library)
            let withLine = GraphPanelLayout.canvasFrame(inPanelOf: size, flow: flow, showsLibrary: library, showsRefusal: true)
            #expect(withLine.origin == plain.origin && withLine.size == plain.size - line)
        }
        #expect(GraphPanelLayout.libraryFrame(inPanelOf: size, flow: .horizontal, showsRefusal: true).size
                == GraphPanelLayout.libraryFrame(inPanelOf: size, flow: .horizontal).size - line)
    }

    @Test func theCanvasShrinksWhileARefusalShows() {
        let editor = makeEditor([], dock: .bottom)
        let panel = CanvasRect(origin: Vector2(12, 388), size: Vector2(976, 300))
        editor.placement = { PanelPlacement(window: Vector2(1000, 700), panel: panel) }
        #expect(editor.canvasFrameInWindow?.size == Vector2(772, 244))
        #expect(editor.drawnCanvasRect != nil)
        editor.refuse("No.", node: nil)
        #expect(editor.canvasFrameInWindow?.size == Vector2(772, 220), "one 16-point line and the 8 points above it")
        #expect(editor.visibleCanvasCentre == Vector2(386, 110))
        editor.clearRefusal()
        #expect(editor.canvasFrameInWindow?.size == Vector2(772, 244))
    }

    @Test func theHostPlacesTheCanvasInTheWindow() {
        let editor = makeEditor([], dock: .bottom)
        #expect(editor.canvasFrameInWindow == nil, "no host, no window coordinates")
        let panel = CanvasRect(origin: Vector2(12, 388), size: Vector2(976, 300))
        editor.placement = { PanelPlacement(window: Vector2(1000, 700), panel: panel) }
        #expect(editor.canvasFrameInWindow == CanvasRect(origin: Vector2(206, 434), size: Vector2(772, 244)))
        #expect(editor.windowPoint(fromCanvas: Vector2(5, 6)) == Vector2(211, 440))
        #expect(editor.visibleCanvasCentre == Vector2(386, 122))
        editor.toggleLibrary()
        #expect(editor.canvasFrameInWindow == CanvasRect(origin: Vector2(22, 434), size: Vector2(956, 244)))
        editor.setDock(.hidden)
        #expect(editor.canvasFrameInWindow == nil, "a hidden panel has no canvas")
    }

    /// The header and the library are framed to `GraphPanelLayout`, so the canvas starts where the layout says: a
    /// node at the canvas origin, unpanned and unzoomed, is drawn at `canvasFrame`'s origin.
    @Test(arguments: [(DockSide.left, true), (.left, false), (.bottom, true), (.bottom, false)])
    func aNodeAtTheCanvasOriginIsDrawnWhereTheLayoutPutsTheCanvas(_ dock: DockSide, _ library: Bool) {
        let editor = makeEditor([testNode(NumberTestNode.self, id: 1, at: .zero)], dock: dock)
        if !library { editor.toggleLibrary() }
        let input = GraphPanelInput(model: editor)
        let scene = renderHeadless { GraphPanel(model: editor, input: input) }
        let scale = 2.0
        let origin = GraphPanelLayout.canvasFrame(inPanelOf: Vector2(900, 600), flow: editor.flow, showsLibrary: library).origin
        let body = scene.rects.contains { rect in
            abs(Double(rect.bounds.origin.x) / scale - origin.x) < 0.5
                && abs(Double(rect.bounds.origin.y) / scale - origin.y) < 0.5
                && abs(Double(rect.bounds.size.width) / scale - NodeLayout.width) < 0.5
        }
        #expect(body, "no node drawn at \(origin)")
    }
}
