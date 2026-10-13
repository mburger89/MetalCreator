import MetalUI

/// Puts the legend at the viewport's lower left, above the axis triad and clear of the docked graph panel
/// (`AppLayout.legendInsets`). It fills the window so the card can stand in a corner; only the card itself is drawn.
struct FieldLegendDock: Component {
    let model: AppModel

    var content: some ElementGroup {
        let insets = AppLayout.legendInsets(dock: model.editor.dock, panelWidth: model.panelWidth, panelHeight: model.panelHeight)
        VStack(alignment: .leading, spacing: Pixels(0)) {
            Spacer()
            HStack(spacing: Pixels(0)) {
                FieldLegendView(model: model)
                Spacer()
            }
        }
        .padding(Edges(top: Pixels(0), right: Pixels(0), bottom: insets.bottom.px, left: insets.leading.px))
    }
}
