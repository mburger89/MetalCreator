import MetalUI

/// The graph panel under its header (`GraphPanelLayout`): the canvas, with the node library as a column at its
/// left edge (docked at the bottom) or a strip across its top (docked left) while it is shown.
///
/// The library is drawn after the canvas, over the room the canvas is inset from, so a node panned past the canvas's
/// edge goes under the library's opaque background rather than over it. The canvas's own clip should already stop
/// it there, but a node's `clipShape` under the canvas's pan and zoom loses that clip (gap LF-a); drawing the library
/// last is right either way.
struct GraphPanelBody: Component {
    let model: EditorModel
    let input: GraphPanelInput

    var content: some ElementGroup {
        let extent = GraphPanelLayout.libraryExtent.px
        let inset = (GraphPanelLayout.libraryExtent + GraphPanelLayout.spacing).px
        if !model.showsLibrary {
            GraphCanvas(model: model, input: input)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.flow == .horizontal {
            ZStack(alignment: .topLeading) {
                // In a ZStack the canvas (a Component) is adopted as proposal content, which takes edge padding.
                ZStack { GraphCanvas(model: model, input: input) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(Edges(top: Pixels(0), right: Pixels(0), bottom: Pixels(0), left: inset))
                NodeLibraryView(model: model, input: input)
                    .frame(width: extent)
                    .frame(maxHeight: .infinity)
            }
        } else {
            ZStack(alignment: .topLeading) {
                // In a ZStack the canvas (a Component) is adopted as proposal content, which takes edge padding.
                ZStack { GraphCanvas(model: model, input: input) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(Edges(top: inset, right: Pixels(0), bottom: Pixels(0), left: Pixels(0)))
                NodeLibraryView(model: model, input: input)
                    .frame(height: extent)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
