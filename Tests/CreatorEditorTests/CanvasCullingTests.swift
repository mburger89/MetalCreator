import CreatorGeometry
import CreatorGraph
import MetalUI
import Testing
@testable import CreatorEditor

/// The canvas draws only what can show (spec §7.3's 50-node pan, docs/verification/performance.md): nodes and wires
/// wholly outside the canvas grown by `EditorModel.cullingMargin` aren't built, so a frame's cost follows what's in
/// view, not the graph's size. Hit testing never culls (it's the model's, from `NodeLayout`).
@MainActor
struct CanvasCullingTests {
    static let window = Vector2(1000, 700)
    static let panel = CanvasRect(origin: Vector2(12, 388), size: Vector2(976, 300))

    func placed(_ editor: EditorModel) -> EditorModel {
        editor.placement = { PanelPlacement(window: Self.window, panel: Self.panel) }
        return editor
    }

    func canvasSize(_ editor: EditorModel) -> Vector2 {
        GraphPanelLayout.canvasFrame(inPanelOf: Self.panel.size, flow: editor.flow, showsLibrary: editor.showsLibrary).size
    }

    /// A Rectangle test node drawn with its top-left corner at `display` (display canvas points) in `dock`.
    func node(_ id: Int, drawnAt display: Vector2, dock: DockSide) -> Node {
        testNode(RectangleTestNode.self, id: id, at: CanvasFlow(dock).stored(display))
    }

    @Test func anUnplacedPanelDrawsEveryNode() {
        let editor = makeEditor([node(1, drawnAt: .zero, dock: .bottom), node(2, drawnAt: Vector2(9_000, 9_000), dock: .bottom)])
        #expect(editor.drawnCanvasRect == nil)
        #expect(editor.drawnNodes.map(\.id) == editor.drawOrder.map(\.id))
    }

    @Test func aHiddenPanelHasNoDrawnRect() {
        let editor = placed(makeEditor([], dock: .hidden))
        #expect(editor.drawnCanvasRect == nil)
    }

    @Test func theDrawnRectIsTheCanvasGrownByTheMarginUnderTheTransform() throws {
        let editor = placed(makeEditor([]))
        let size = canvasSize(editor)
        let margin = EditorModel.cullingMargin
        editor.transform = CanvasTransform(offset: Vector2(-100, -50), zoom: 1)
        let plain = try #require(editor.drawnCanvasRect)
        #expect(plain.origin == Vector2(100 - margin, 50 - margin))
        #expect(plain.size == size + Vector2(2 * margin, 2 * margin))
        editor.transform = CanvasTransform(offset: Vector2(40, 0), zoom: 2)
        let zoomed = try #require(editor.drawnCanvasRect)
        #expect(zoomed.origin == Vector2((-margin - 40) / 2, -margin / 2))
        #expect(zoomed.size == (size + Vector2(2 * margin, 2 * margin)) * 0.5)
    }

    @Test(arguments: [DockSide.bottom, .left])
    func nodesWhollyOutsideTheDrawnRectAreNotDrawn(dock: DockSide) {
        let editor = placed(makeEditor([], dock: dock))
        let width = canvasSize(editor).x
        let nodes = [
            node(1, drawnAt: Vector2(20, 20), dock: dock),             // in view
            node(2, drawnAt: Vector2(width + 100, 20), dock: dock),    // past the right edge, within the margin
            node(3, drawnAt: Vector2(width + 200, 20), dock: dock),    // past the margin
            node(4, drawnAt: Vector2(-100, 20), dock: dock),           // straddling the left edge
            node(5, drawnAt: Vector2(-400, 20), dock: dock),           // wholly left of the margin
        ]
        let culled = placed(makeEditor(nodes, dock: dock))
        #expect(culled.drawnNodes.map(\.id) == [nodeID(1), nodeID(2), nodeID(4)])
    }

    @Test func zoomingOutDrawsMore() {
        let editor = placed(makeEditor([]))
        let far = node(1, drawnAt: Vector2(canvasSize(editor).x * 1.5, 20), dock: .bottom)
        let culled = placed(makeEditor([far]))
        #expect(culled.drawnNodes.isEmpty)
        culled.transform = CanvasTransform(offset: .zero, zoom: 0.5)
        #expect(culled.drawnNodes.map(\.id) == [far.id])
    }

    @Test func theDrawOrderIsKept() {
        let nodes = (1...4).map { node($0, drawnAt: Vector2(Double($0) * 30, 20), dock: .bottom) }
        let editor = placed(makeEditor(nodes))
        editor.selection = [nodeID(2)]
        #expect(editor.drawnNodes.map(\.id) == editor.drawOrder.map(\.id))
        #expect(editor.drawnNodes.last?.id == nodeID(2), "the selection is still raised")
    }

    @Test func aWireIsDrawnWhileAnyOfItCanShow() {
        let inView = testNode(RectangleTestNode.self, id: 1, at: .zero)
        let farRight = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(3_000, 0))
        let farA = testNode(RectangleTestNode.self, id: 3, at: Vector2(3_000, 600))
        let farB = testNode(ExtrudeTestNode.self, id: 4, at: Vector2(3_400, 600))
        let links = [wire(inView, "profile", farRight, "profile"), wire(farA, "profile", farB, "profile")]
        let unplaced = makeEditor([inView, farRight, farA, farB], links)
        #expect(CanvasLayers.wires(unplaced).count == 2)
        let culled = placed(makeEditor([inView, farRight, farA, farB], links))
        #expect(CanvasLayers.wires(culled).map(\.id) == ["\(nodeID(2).rawValue.uuidString).profile"],
                "the wire leaving the view stays; the one wholly outside goes")
    }

    /// A wire whose two ends are both outside the drawn rect, on either side of it, still crosses the view.
    @Test func aWireCrossingTheViewWithBothEndsOutsideIsDrawn() {
        let editor = placed(makeEditor([]))
        let width = canvasSize(editor).x
        let left = testNode(RectangleTestNode.self, id: 1, at: Vector2(-1_200, 40))
        let right = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(width + 1_000, 40))
        let culled = placed(makeEditor([left, right], [wire(left, "profile", right, "profile")]))
        #expect(culled.drawnNodes.isEmpty, "set up: both nodes are culled")
        #expect(CanvasLayers.wires(culled).count == 1)
    }

    /// The drawn rect follows the host's placement each time it's read: a window grown since the last frame draws the
    /// nodes it uncovers.
    @Test func aBiggerWindowDrawsMore() {
        let editor = placed(makeEditor([]))
        let far = node(1, drawnAt: Vector2(canvasSize(editor).x + 400, 20), dock: .bottom)
        let culled = placed(makeEditor([far]))
        #expect(culled.drawnNodes.isEmpty)
        let wider = CanvasRect(origin: Self.panel.origin, size: Self.panel.size + Vector2(800, 0))
        culled.placement = { PanelPlacement(window: Self.window + Vector2(800, 0), panel: wider) }
        #expect(culled.drawnNodes.map(\.id) == [far.id])
    }

    @Test func rowsAreLeftOutBelowHalfZoom() {
        let editor = makeEditor([])
        #expect(editor.drawsNodeRows)
        editor.transform = CanvasTransform(offset: .zero, zoom: EditorModel.rowsMinimumZoom)
        #expect(editor.drawsNodeRows, "at the threshold, rows still draw")
        editor.transform = CanvasTransform(offset: .zero, zoom: 0.45)
        #expect(!editor.drawsNodeRows)
    }

    /// Zoomed out, a node still paints its header's title, but not its rows' text.
    @Test func aZoomedOutNodeDrawsWithoutItsRows() {
        let node = testNode(RectangleTestNode.self, id: 1, at: Vector2(20, 20))
        func glyphs(_ nodes: [Node], zoom: Double) -> Int {
            let editor = makeEditor(nodes)
            editor.transform = CanvasTransform(offset: .zero, zoom: zoom)
            return renderHeadless { GraphPanel(model: editor, input: GraphPanelInput(model: editor)) }.glyphs.count
        }
        let empty = glyphs([], zoom: 0.45), withRows = glyphs([node], zoom: 0.5), withoutRows = glyphs([node], zoom: 0.45)
        #expect(withoutRows > empty, "the title still paints")
        #expect(withoutRows < withRows, "the rows' text doesn't")
    }

    /// Culling is drawing only: a selected node out of view is still the selection's, and deleting the selection
    /// deletes it.
    @Test func aSelectedNodeOutOfViewIsStillEdited() {
        let far = node(1, drawnAt: Vector2(9_000, 20), dock: .bottom)
        let editor = placed(makeEditor([far]))
        editor.selection = [far.id]
        #expect(editor.drawnNodes.isEmpty, "set up: the node is culled")
        #expect(editor.perform(.deleteSelection))
        #expect(editor.graph.nodes.isEmpty)
    }

    /// Culling never takes a node that shows: with twenty nodes far off the canvas, the node in view and the one
    /// straddling the canvas's right edge still paint at those points.
    @Test func theNodesInViewStillPaint() {
        let size = Vector2(900, 600)
        let canvas = GraphPanelLayout.canvasFrame(inPanelOf: size, flow: .horizontal, showsLibrary: true)
        let inView = testNode(RectangleTestNode.self, id: 1, at: Vector2(20, 20))
        let straddling = testNode(RectangleTestNode.self, id: 2, at: Vector2(canvas.size.x - 60, 20))
        let far = (3...22).map { testNode(RectangleTestNode.self, id: $0, at: Vector2(Double($0) * 200 + 2_000, 20)) }
        let editor = makeEditor([inView, straddling] + far)
        editor.placement = { PanelPlacement(window: size, panel: CanvasRect(origin: .zero, size: size)) }
        #expect(editor.drawnNodes.map(\.id) == [nodeID(1), nodeID(2)])
        let scene = renderHeadless { GraphPanel(model: editor, input: GraphPanelInput(model: editor)) }
        for (node, inset) in [(inView, Vector2(40, 60)), (straddling, Vector2(30, 60))] {
            let frame = editor.frame(of: node)
            let onScreen = CanvasRect(origin: canvas.origin + frame.origin - Vector2(1, 1), size: frame.size + Vector2(2, 2))
            let painted = topRect(at: canvas.origin + frame.origin + inset, in: scene).map { screenFrame(of: $0, in: scene) }
            #expect(painted.map { onScreen.contains($0.origin) && onScreen.contains($0.origin + $0.size) } == true,
                    "\(node.id): what paints there is part of the node")
        }
    }
}
