import MetalUI

/// The graph canvas: its surface (`CanvasSurface`, which takes all the input) with the editing layer over it
/// (`CommentEditorLayer`, a note or a frame's title being typed into in place). The palette itself floats over the whole
/// window (`SearchPaletteOverlay`), so the canvas never clips it.
struct GraphCanvas: Component, Equatable {
    let model: EditorModel
    let input: GraphPanelInput

    /// Compares the models by identity: they are final `@Observable` classes, so MetalUI re-evaluates this view when a
    /// property its content read changes, and `==` need only say the inputs are the same objects.
    nonisolated static func == (lhs: GraphCanvas, rhs: GraphCanvas) -> Bool { lhs.model === rhs.model && lhs.input === rhs.input }

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            CanvasSurface(model: model, input: input).equatable()
            CommentEditorLayer(model: model)
        }
        .clipped()
        .onContinuousHover(coordinateSpace: .global) { phase in input.windowHover(phase) }
    }
}
