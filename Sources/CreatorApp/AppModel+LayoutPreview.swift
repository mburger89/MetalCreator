import CreatorGraph
import CreatorViewport

extension AppModel {
    /// The layout preview for the one node selected in the level shown (`LayoutPreview`), or nothing: while picking, the
    /// sketch editor draws its own overlay, so this is never asked then.
    var layoutOverlay: ViewportOverlay {
        guard editor.selection.count == 1, let id = editor.selection.first, let node = editor.graph.nodes[id] else {
            return ViewportOverlay()
        }
        return LayoutPreview.overlay(for: node, graph: editor.graph, results: editor.levelResults)
    }
}
