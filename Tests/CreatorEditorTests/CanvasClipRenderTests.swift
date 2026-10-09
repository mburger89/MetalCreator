import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// Canvas content never paints outside the canvas: a node panned under the node library (a strip across the canvas's
/// top docked left, a column at its left docked at the bottom) or up past the panel's header is hidden there, and
/// what shows at that point is the library or the header, not the node.
@MainActor
struct CanvasClipRenderTests {
    static let panel = Vector2(900, 600)

    /// A Rectangle node panned so its top-left corner is `screen` in the panel (window points), and the scene.
    func render(dock: DockSide, nodeAt screen: Vector2, zoom: Double = 1,
                showsLibrary: Bool = true) -> (EditorModel, Scene, CanvasRect) {
        let rect = testNode(RectangleTestNode.self, id: 1, at: .zero)
        let editor = makeEditor([rect], dock: dock)
        if editor.showsLibrary != showsLibrary { editor.toggleLibrary() }
        let canvas = GraphPanelLayout.canvasFrame(inPanelOf: Self.panel, flow: editor.flow, showsLibrary: editor.showsLibrary)
        let frame = editor.graph.nodes[nodeID(1)].map { editor.frame(of: $0) } ?? CanvasRect(origin: .zero, size: .zero)
        editor.transform = CanvasTransform(offset: screen - canvas.origin - frame.origin * zoom, zoom: zoom)
        let input = GraphPanelInput(model: editor)
        let scene = renderHeadless { GraphPanel(model: editor, input: input) }
        let drawn = CanvasRect(origin: screen, size: frame.size * zoom)
        return (editor, scene, drawn)
    }

    /// Whether the rect painted last at `point` is part of the node drawn at `node` (lies within it).
    func nodeShows(at point: Vector2, in scene: Scene, node: CanvasRect) -> Bool {
        guard let rect = topRect(at: point, in: scene) else { return false }
        let bounds = screenFrame(of: rect, in: scene)
        let slack = CanvasRect(origin: node.origin - Vector2(1, 1), size: node.size + Vector2(2, 2))
        return slack.contains(bounds.origin) && slack.contains(bounds.origin + bounds.size)
    }

    @Test(arguments: [1.0, 1.5])
    func aNodeUnderTheLibraryStripIsHiddenByIt(zoom: Double) {
        let (editor, scene, node) = render(dock: .left, nodeAt: Vector2(60, 120), zoom: zoom)
        let library = GraphPanelLayout.libraryFrame(inPanelOf: Self.panel, flow: editor.flow)
        let canvas = GraphPanelLayout.canvasFrame(inPanelOf: Self.panel, flow: editor.flow, showsLibrary: true)
        #expect(node.origin.y < library.maxY && node.maxY > canvas.origin.y, "set up: the node spans the strip's edge")
        #expect(nodeShows(at: Vector2(node.origin.x + 30, canvas.origin.y + 10), in: scene, node: node),
                "set up: the node shows in the canvas")
        #expect(!nodeShows(at: Vector2(node.origin.x + 30, library.maxY - 10), in: scene, node: node),
                "the node paints over the library strip")
    }

    @Test(arguments: [1.0, 1.5])
    func aNodeUnderTheLibraryColumnIsHiddenByIt(zoom: Double) {
        let (editor, scene, node) = render(dock: .bottom, nodeAt: Vector2(120, 100), zoom: zoom)
        let library = GraphPanelLayout.libraryFrame(inPanelOf: Self.panel, flow: editor.flow)
        let canvas = GraphPanelLayout.canvasFrame(inPanelOf: Self.panel, flow: editor.flow, showsLibrary: true)
        #expect(node.origin.x < library.maxX && node.maxX > canvas.origin.x, "set up: the node spans the column's edge")
        #expect(nodeShows(at: Vector2(canvas.origin.x + 10, node.origin.y + 60), in: scene, node: node),
                "set up: the node shows in the canvas")
        #expect(!nodeShows(at: Vector2(library.maxX - 10, node.origin.y + 60), in: scene, node: node),
                "the node paints over the library column")
    }

    /// Known to fail (gap LF-a): a node's own `clipShape` under the canvas's offset loses the canvas's clip, so the
    /// node paints over the header, which has no opaque fill to hide it the way the library's does.
    @Test(arguments: [DockSide.left, .bottom])
    func aNodeAboveTheCanvasNeverCoversTheHeader(dock: DockSide) {
        let header = GraphPanelLayout.glassPadding + GraphPanelLayout.headerHeight / 2
        let (editor, scene, node) = render(dock: dock, nodeAt: Vector2(300, header - 10), showsLibrary: false)
        let canvas = GraphPanelLayout.canvasFrame(inPanelOf: Self.panel, flow: editor.flow, showsLibrary: false)
        #expect(nodeShows(at: Vector2(node.origin.x + 30, canvas.origin.y + 10), in: scene, node: node),
                "set up: the node shows in the canvas")
        withKnownIssue("LF-a: a clip inside an offset or a scale forgets the clip outside it") {
            #expect(!nodeShows(at: Vector2(node.origin.x + 30, header), in: scene, node: node),
                    "the node paints over the panel's header")
        }
    }
}
