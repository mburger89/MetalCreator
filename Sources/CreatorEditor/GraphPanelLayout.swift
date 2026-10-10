import CreatorGeometry
import CreatorGraph

/// The graph panel's own geometry, computed rather than measured (MetalUI has no geometry reader:
/// docs/metalui-gaps.md M4-a, EP-a), so the editor can tell where its canvas is in the window. `GlassPanel`,
/// `GraphPanel`, `GraphPanelHeader` and `GraphPanelBody` are framed to these numbers, as nodes are framed to
/// `NodeLayout`.
///
/// Under the header is the body: the node library and the canvas. The library sits on the side the graph flows
/// from, across the panel's short axis: a column at the canvas's left edge when docked at the bottom (the graph
/// flows right; the panel is wide and short), a strip across its top when docked left (the graph flows down; the
/// panel is narrow and tall), so it takes the room the panel has most of.
public enum GraphPanelLayout {
    /// The glass chrome's inset around its content (`GlassPanel`).
    public static let glassPadding = 10.0
    /// The header row (title and buttons).
    public static let headerHeight = 28.0
    /// Between the header and the body, and between the library and the canvas.
    public static let spacing = 8.0
    /// The library's column width (docked at the bottom) or strip height (docked left).
    public static let libraryExtent = 176.0
    /// The canvas size assumed while the host hasn't placed the panel (headless tests): the centre of a small panel.
    public static let fallbackCanvasSize = Vector2(400, 300)

    /// The body under the header inside a panel of `size`, in panel-local points. It runs to the panel's padding; a
    /// refusal message showing under it takes one line from its bottom.
    public static func bodyFrame(inPanelOf size: Vector2) -> CanvasRect {
        let origin = Vector2(glassPadding, glassPadding + headerHeight + spacing)
        return CanvasRect(origin: origin, size: Vector2(max(0, size.x - 2 * glassPadding),
                                                        max(0, size.y - origin.y - glassPadding)))
    }

    /// The node library's frame in the body, for a panel of `size` showing the graph in `flow`.
    public static func libraryFrame(inPanelOf size: Vector2, flow: CanvasFlow) -> CanvasRect {
        let body = bodyFrame(inPanelOf: size)
        switch flow {
        case .horizontal: return CanvasRect(origin: body.origin, size: Vector2(min(libraryExtent, body.size.x), body.size.y))
        case .vertical: return CanvasRect(origin: body.origin, size: Vector2(body.size.x, min(libraryExtent, body.size.y)))
        }
    }

    /// The canvas's frame: the whole body, or the body beside or below the library.
    public static func canvasFrame(inPanelOf size: Vector2, flow: CanvasFlow, showsLibrary: Bool) -> CanvasRect {
        let body = bodyFrame(inPanelOf: size)
        guard showsLibrary else { return body }
        let inset = libraryExtent + spacing
        switch flow {
        case .horizontal:
            return CanvasRect(origin: body.origin + Vector2(inset, 0), size: Vector2(max(0, body.size.x - inset), body.size.y))
        case .vertical:
            return CanvasRect(origin: body.origin + Vector2(0, inset), size: Vector2(body.size.x, max(0, body.size.y - inset)))
        }
    }
}
