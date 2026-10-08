import CreatorGraph
import MetalUI

/// The graph panel (spec §6.2): glass chrome, the header and the canvas, with a refusal message
/// along the bottom while one is showing. The app shell (M6) sizes and places it per dock and
/// installs the input with `input.install(on:)`.
public struct GraphPanel: Component {
    public let model: EditorModel
    public let input: GraphPanelInput

    public init(model: EditorModel, input: GraphPanelInput) {
        self.model = model
        self.input = input
    }

    public var content: some ElementGroup {
        GlassPanel {
            VStack(alignment: .leading, spacing: Pixels(8)) {
                GraphPanelHeader(model: model)
                GraphCanvas(model: model, input: input)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let refusal = model.refusal {
                    Text(refusal.message).font(.caption).foregroundStyle(Palette.statusError.color)
                }
            }
        }
    }
}
