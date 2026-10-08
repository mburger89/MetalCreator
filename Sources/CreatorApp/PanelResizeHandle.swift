import CreatorEditor
import CreatorStyle
import MetalUI

/// The graph panel's inner edge (spec §6.1): dragging it resizes the panel. No pointer style until MetalUI C7
/// merges; then adopt `.pointerStyle(.columnResize)` / `.rowResize` (C7 decision CI-H). Until then it is a
/// visible hairline strip.
struct PanelResizeHandle: Component {
    let model: AppModel
    /// True for the left dock's vertical edge, dragged sideways; false for the bottom dock's top edge.
    let alongWidth: Bool
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        Palette(themes).hairline.color
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gesture(
                DragGesture(minimumDistance: Pixels(0))
                    .onChanged { value in
                        if !model.isResizingPanel { model.beginPanelResize() }
                        let translation = alongWidth ? value.translation.width : value.translation.height
                        model.resizePanel(by: Double(translation.value))
                    }
                    .onEnded { _ in model.endPanelResize() }
            )
            .help("Drag to resize the graph panel")
    }
}
