import MetalUI

/// The graph panel under its header (`GraphPanelLayout`): the canvas, with the node library as a column at its
/// left edge (docked at the bottom) or a strip across its top (docked left) while it is shown.
struct GraphPanelBody: Component {
    let model: EditorModel
    let input: GraphPanelInput

    var content: some ElementGroup {
        let extent = GraphPanelLayout.libraryExtent.px
        let spacing = GraphPanelLayout.spacing.px
        if !model.showsLibrary {
            GraphCanvas(model: model, input: input)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.flow == .horizontal {
            HStack(alignment: .top, spacing: spacing) {
                NodeLibraryView(model: model, input: input)
                    .frame(width: extent)
                    .frame(maxHeight: .infinity)
                GraphCanvas(model: model, input: input)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                NodeLibraryView(model: model, input: input)
                    .frame(height: extent)
                    .frame(maxWidth: .infinity)
                GraphCanvas(model: model, input: input)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
