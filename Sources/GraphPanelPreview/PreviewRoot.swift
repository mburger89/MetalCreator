import CreatorEditor
import MetalUI

/// The preview window's content: the window background, the graph panel in its dock and the
/// inspector on the right — the layout the app shell (M6) will float over the viewport.
struct PreviewRoot: Component {
    let model: EditorModel
    let input: GraphPanelInput

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            Palette.dracula.backgroundBottom.color
            switch model.dock {
            case .left:
                HStack(alignment: .top, spacing: Pixels(12)) {
                    ZStack { GraphPanel(model: model, input: input) }.frame(width: Pixels(380))
                    Spacer()
                    InspectorPanel(model: model)
                }
                .padding(Edges(all: Pixels(12)))
            case .bottom:
                VStack(spacing: Pixels(12)) {
                    HStack(alignment: .top) {
                        Spacer()
                        InspectorPanel(model: model)
                    }
                    ZStack { GraphPanel(model: model, input: input) }.frame(height: Pixels(300))
                }
                .padding(Edges(all: Pixels(12)))
            case .hidden:
                // Hidden keeps a visible way back: "Show graph" (Tab is its shortcut).
                HStack(alignment: .bottom) {
                    GraphShowButton(model: model)
                    Spacer()
                    InspectorPanel(model: model)
                }
                .padding(Edges(all: Pixels(12)))
            }
        }
    }
}
