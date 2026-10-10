import CreatorEditor
import MetalUI

/// The preview window's content: the window background, the graph panel in its dock and the
/// inspector on the right — the layout the app shell (M6) floats over the viewport — and the
/// add-node palette and a dragged node-library type floating over all of it. It is laid out to
/// `PreviewLayout`, which tells the editor where the panel is.
struct PreviewRoot: Component {
    let model: EditorModel
    let input: GraphPanelInput

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            WindowBackground()
            switch model.dock {
            case .left:
                HStack(alignment: .top, spacing: PreviewLayout.margin.px) {
                    ZStack { GraphPanel(model: model, input: input) }
                        .frame(width: PreviewLayout.leftPanelWidth.px)
                        .frame(maxHeight: .infinity)
                    Spacer()
                    InspectorPanel(model: model)
                }
                .padding(Edges(all: PreviewLayout.margin.px))
            case .bottom:
                VStack(spacing: PreviewLayout.margin.px) {
                    HStack(alignment: .top) {
                        Spacer()
                        InspectorPanel(model: model)
                    }
                    Spacer()
                    ZStack { GraphPanel(model: model, input: input) }
                        .frame(height: PreviewLayout.bottomPanelHeight.px)
                        .frame(maxWidth: .infinity)
                }
                .padding(Edges(all: PreviewLayout.margin.px))
            case .hidden:
                // Hidden keeps a visible way back: "Show graph" (Tab is its shortcut).
                HStack(alignment: .bottom) {
                    GraphShowButton(model: model)
                    Spacer()
                    InspectorPanel(model: model)
                }
                .padding(Edges(all: PreviewLayout.margin.px))
            }
            SearchPaletteOverlay(model: model)
            LibraryDragOverlay(model: model)
        }
        .frame(width: PreviewLayout.window.x.px, height: PreviewLayout.window.y.px)
    }
}
