import CreatorGraph
import CreatorStyle
import MetalUI

/// The graph panel (spec §6.2): glass chrome, the header, and the body (the node library and the
/// canvas), with a refusal message along the bottom while one is showing. It is laid out to
/// `GraphPanelLayout`, so the host's
/// `EditorModel.placement` tells the editor where the canvas is in the window. The app shell (M6)
/// sizes and places it per dock and installs the input with `input.install(on:)`.
public struct GraphPanel: Component {
    public let model: EditorModel
    public let input: GraphPanelInput
    @Environment(ThemeStore.self) var themes: ThemeStore?

    public init(model: EditorModel, input: GraphPanelInput) {
        self.model = model
        self.input = input
    }

    public var content: some ElementGroup {
        ZStack {
            // The glass only paints, and MetalUI gives a painted view no hitbox (its divergence 141), so without this
            // backdrop a scroll, pinch, press or hover over the header's gaps, the padding or the refusal line would
            // reach the viewport beneath. Opaque (a content shape with an empty drag) and claiming every scroll, as
            // the palette's backdrop is (docs/metalui-gaps.md EP-b). The canvas, the header's buttons and the
            // library's list are drawn above it and take their own input.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: Pixels(0)))
                .onScrollWheel { _ in true }
            GlassPanel {
                VStack(alignment: .leading, spacing: GraphPanelLayout.spacing.px) {
                    GraphPanelHeader(model: model)
                        .frame(height: GraphPanelLayout.headerHeight.px)
                    GraphPanelBody(model: model, input: input)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let refusal = model.refusal {
                        Text(refusal.message).font(.caption).foregroundStyle(Palette(themes).statusError.color)
                    }
                }
            }
        }
    }
}
