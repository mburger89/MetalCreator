import CreatorGraph
import CreatorKernel
import CreatorViewport

extension AppModel {
    /// A preview of the field of the one node selected in the level shown, over the opaque parts of `scene`, or `nil`: while
    /// picking or sketching, with no node or several selected, or when the node has no field to show
    /// (`FieldPreviewSelection`). The slice starts from the camera's view direction at the moment a new node is selected.
    func fieldPreviewRequest(for scene: [SceneItem]) -> FieldPreviewRequest? {
        guard pick == nil, sketch == nil, editor.selection.count == 1, let id = editor.selection.first,
              let node = editor.graph.nodes[id],
              let field = FieldPreviewSelection.field(of: node, graph: editor.graph, results: editor.levelResults,
                                                      registry: registry) else { return nil }
        var seen = Set<ObjectIdentifier>()
        let solids = scene.map(\.item).filter { !$0.isGhost && !$0.isGuide }.map(\.solid)
            .filter { seen.insert(ObjectIdentifier($0)).inserted }
        return FieldPreviewRequest(node: id, field: field, solids: solids, toEye: viewport.pose.toEye)
    }

    /// A preview model for a document's parts: it samples through the evaluator's distance cache and reads a solid's vertices
    /// from the viewport once it has meshed the scene.
    static func makeFieldPreview(kernel: any Kernel, parts: DocumentParts) -> FieldPreviewModel {
        let viewport = parts.viewport
        return FieldPreviewModel(kernel: kernel, distances: parts.document.fieldDistances) { solid in
            await viewport.waitForMeshes()
            return viewport.displayMesh(of: solid)
        }
    }
}
