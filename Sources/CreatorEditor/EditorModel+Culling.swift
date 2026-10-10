import CreatorGeometry
import CreatorGraph

extension EditorModel {
    /// How far past the canvas's edges, in screen points, nodes and wires are still drawn. It covers a refused node's
    /// shake and its sockets' overhang, and the one frame of a window resize before the canvas is rebuilt at the new
    /// size (`ViewportModel.observedViewSize`, docs/metalui-gaps.md M4-a).
    public static let cullingMargin = 160.0

    /// The part of the canvas that can show, in display canvas points, grown by `cullingMargin` screen points on every
    /// side; `nil` while the host hasn't placed the panel (headless tests, before the viewport's first draw) or the
    /// panel is hidden, when everything is drawn.
    public var drawnCanvasRect: CanvasRect? {
        guard isPanelVisible, let placement = panelPlacement else { return nil }
        let size = GraphPanelLayout.canvasFrame(inPanelOf: placement.panel.size, flow: flow, showsLibrary: showsLibrary).size
        let margin = Vector2(Self.cullingMargin, Self.cullingMargin)
        return CanvasRect(corner: transform.toCanvas(.zero - margin), transform.toCanvas(size + margin))
    }

    /// The zoom below which nodes are drawn without their rows (header, body and sockets only): a row's text is under
    /// about 5 points tall there, too small to read, and leaving the rows out takes about a third off a zoomed-out
    /// frame (docs/verification/performance.md, "What MetalCreator changed").
    public static let rowsMinimumZoom = 0.5

    /// Whether the canvas draws each node's rows: false while zoomed out below `rowsMinimumZoom`. Drawing only: a
    /// node keeps its `NodeLayout` size, and hit testing is unchanged.
    public var drawsNodeRows: Bool { transform.zoom >= Self.rowsMinimumZoom }

    /// The nodes the canvas builds, back to front: `drawOrder` without the nodes wholly outside `drawnCanvasRect`
    /// (spec §7.3: a frame's cost follows what's in view, not the graph's size).
    public var drawnNodes: [Node] {
        guard let drawn = drawnCanvasRect else { return drawOrder }
        return drawOrder.filter { drawn.intersects(frame(of: $0)) }
    }
}
