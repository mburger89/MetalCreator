import MetalUI

/// Puts the mesh badge at the viewport's lower right, clear of the docked panels (`AppLayout.badgeInsets`). It fills the window so the
/// badge can stand in a corner; only the badge itself is drawn.
struct MeshBadgeDock: Component {
    let model: AppModel

    var content: some ElementGroup {
        let insets = AppLayout.badgeInsets(dock: model.editor.dock, panelWidth: model.panelWidth, panelHeight: model.panelHeight)
        VStack(alignment: .trailing, spacing: Pixels(0)) {
            Spacer()
            HStack(spacing: Pixels(0)) {
                Spacer()
                MeshBadgeView(model: model)
            }
        }
        .padding(Edges(top: Pixels(0), right: insets.trailing.px, bottom: insets.bottom.px, left: Pixels(0)))
    }
}
