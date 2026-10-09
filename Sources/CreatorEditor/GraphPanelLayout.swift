import CreatorGeometry

/// The graph panel's own geometry, computed rather than measured (MetalUI has no geometry reader:
/// docs/metalui-gaps.md M4-a, EP-a), so the editor can tell where its canvas is in the window. `GlassPanel`,
/// `GraphPanel` and `GraphPanelHeader` are framed to these numbers, as nodes are framed to `NodeLayout`.
public enum GraphPanelLayout {
    /// The glass chrome's inset around its content (`GlassPanel`).
    public static let glassPadding = 10.0
    /// The header row (title and buttons).
    public static let headerHeight = 28.0
    /// Between the header and the canvas.
    public static let spacing = 8.0
    /// The canvas size assumed while the host hasn't placed the panel (headless tests): the centre of a small panel.
    public static let fallbackCanvasSize = Vector2(400, 300)

    /// The canvas's frame inside a panel of `size`, in panel-local points. It runs to the panel's padding; a
    /// refusal message showing under the canvas takes one line from its bottom.
    public static func canvasFrame(inPanelOf size: Vector2) -> CanvasRect {
        let origin = Vector2(glassPadding, glassPadding + headerHeight + spacing)
        return CanvasRect(origin: origin, size: Vector2(max(0, size.x - 2 * glassPadding),
                                                        max(0, size.y - origin.y - glassPadding)))
    }
}
