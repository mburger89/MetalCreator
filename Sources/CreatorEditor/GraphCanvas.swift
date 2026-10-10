import MetalUI

/// The graph canvas: its surface (`CanvasSurface`, which takes all the input) with the editing layer over it
/// (`CommentEditorLayer`, a note or a frame's title being typed into in place). The palette itself floats over the whole
/// window (`SearchPaletteOverlay`), so the canvas never clips it.
struct GraphCanvas: Component {
    let model: EditorModel
    let input: GraphPanelInput

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            CanvasSurface(model: model, input: input)
            CommentEditorLayer(model: model)
        }
        .clipped()
    }
}
