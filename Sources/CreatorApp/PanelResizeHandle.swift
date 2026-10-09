import CreatorEditor
import CreatorStyle
import MetalUI

/// The graph panel's inner edge (spec §6.1), a visible hairline strip: dragging it resizes the panel, and over it the
/// pointer is a column or row resize cursor (MetalUI C7, `CI-H`), kept while the drag leaves the strip.
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
            .pointerStyle(Self.pointerStyle(alongWidth: alongWidth))
            .help("Drag to resize the graph panel")
    }

    /// The left dock's vertical edge is dragged sideways (a column resize), the bottom dock's top edge up and down
    /// (a row resize).
    static func pointerStyle(alongWidth: Bool) -> PointerStyle {
        alongWidth ? .columnResize : .rowResize
    }
}
