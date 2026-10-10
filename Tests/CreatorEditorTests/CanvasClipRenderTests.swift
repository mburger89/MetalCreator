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

    /// A Rectangle node at `position` on the canvas, panned so its top-left corner is `screen` in the panel (window
    /// points), and the scene.
    func render(dock: DockSide, nodeAt screen: Vector2, zoom: Double = 1, showsLibrary: Bool = true,
                position: Vector2 = .zero) -> (EditorModel, Scene, CanvasRect) {
        let rect = testNode(RectangleTestNode.self, id: 1, at: position)
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

    /// A node's own `clipShape` under the canvas's offset keeps the canvas's clip, so the node never paints over the
    /// header, which has no opaque fill to hide it the way the library's does (gap LF-a, fixed in MetalUI 0b400b4).
    @Test(arguments: [DockSide.left, .bottom])
    func aNodeAboveTheCanvasNeverCoversTheHeader(dock: DockSide) {
        let header = GraphPanelLayout.glassPadding + GraphPanelLayout.headerHeight / 2
        let (editor, scene, node) = render(dock: dock, nodeAt: Vector2(300, header - 10), showsLibrary: false)
        let canvas = GraphPanelLayout.canvasFrame(inPanelOf: Self.panel, flow: editor.flow, showsLibrary: false)
        #expect(nodeShows(at: Vector2(node.origin.x + 30, canvas.origin.y + 10), in: scene, node: node),
                "set up: the node shows in the canvas")
        #expect(!nodeShows(at: Vector2(node.origin.x + 30, header), in: scene, node: node),
                "the node paints over the panel's header (gap LF-a, fixed in MetalUI 0b400b4)")
    }

    /// A node wholly inside the canvas draws whole wherever it sits on the canvas. One at a negative canvas position
    /// (left of and above the canvas's origin before the pan) is the case gap LF-b broke (fixed in MetalUI 9ad2254):
    /// 0b400b4 cut the node's own `clipShape` by the canvas's clip in the space inside the pan and zoom, so only the
    /// slice right of (and below) the canvas's edge moved by the pan painted.
    @Test(arguments: [DockSide.left, .bottom], [1.0, 1.5])
    func aNodeAtANegativeCanvasPositionDrawsWhole(dock: DockSide, zoom: Double) {
        let (editor, scene, node) = render(dock: dock, nodeAt: Vector2(60, 90), zoom: zoom, showsLibrary: false,
                                           position: Vector2(-60, -40))
        let canvas = GraphPanelLayout.canvasFrame(inPanelOf: Self.panel, flow: editor.flow, showsLibrary: false)
        #expect(canvas.contains(node.origin) && canvas.contains(node.origin + node.size), "set up: wholly in the canvas")
        #expect(nodeShows(at: node.origin + node.size * 0.8, in: scene, node: node), "set up: the node's lower right shows")
        #expect(nodeShows(at: node.origin + Vector2(10, 10), in: scene, node: node), "the header's left end")
        #expect(nodeShows(at: node.origin + Vector2(10, node.size.y - 10), in: scene, node: node),
                "the body's bottom-left")
    }
}
