import MetalUI

/// The canvas's editing layer (comments typing plan; spec 2026-10-09 §8): the field of the comment being typed into,
/// or nothing. It sits over the canvas's surface under the same zoom and pan as `CanvasLayers`, so a field built at a
/// comment's canvas rectangle lies exactly over the comment, in either dock, at any zoom, with its text scaled as the
/// comment's is. A sibling of the surface rather than a child: the surface is a key region (`CanvasSurface`), and a
/// field inside it would pass its keys to the canvas's own handler.
struct CommentEditorLayer: Component {
    let model: EditorModel

    var content: some ElementGroup {
        let transform = model.transform
        let editors = model.commentEditor.map { [$0] } ?? []
        return ZStack(alignment: .topLeading) {
            // Keyed by the edit, so a new edit is a new field (focus asked for again), though it sits where the last was.
            ForEach(editors, id: \.edit.owner) { editor in
                CommentEditorField(model: model, editor: editor)
            }
        }
        .scaleEffect(transform.zoom, anchor: .topLeading)
        .offset(x: transform.offset.x.px, y: transform.offset.y.px)
    }
}
