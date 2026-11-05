import MetalUI

/// Puts the slow-evaluation chip at the viewport's lower right, one row above the mesh badge (`AppLayout.slowEvaluationInsets`).
/// It fills the window so the chip can stand in a corner; only the chip itself is drawn.
struct SlowEvaluationDock: Component {
    let model: AppModel

    var content: some ElementGroup {
        let insets = AppLayout.slowEvaluationInsets(dock: model.editor.dock, panelWidth: model.panelWidth, panelHeight: model.panelHeight)
        VStack(alignment: .trailing, spacing: Pixels(0)) {
            Spacer()
            HStack(spacing: Pixels(0)) {
                Spacer()
                SlowEvaluationChipView(model: model)
            }
        }
        .padding(Edges(top: Pixels(0), right: insets.trailing.px, bottom: insets.bottom.px, left: Pixels(0)))
    }
}
