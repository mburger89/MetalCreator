import MetalUI

/// Puts the section panel at the viewport's upper right, under the top bar and clear of the docked panels
/// (`AppLayout.sectionPanelInsets`). It fills the window so the card can stand in a corner; only the card itself is drawn.
struct SectionPanelDock: Component {
    let model: AppModel
    /// Whether the theme editor floats over the inspector column; the panel then stands left of it.
    let themeEditorOpen: Bool

    var content: some ElementGroup {
        let insets = AppLayout.sectionPanelInsets(dock: model.editor.dock, panelWidth: model.panelWidth, panelHeight: model.panelHeight,
                                                themeEditorOpen: themeEditorOpen)
        VStack(alignment: .trailing, spacing: Pixels(0)) {
            HStack(spacing: Pixels(0)) {
                Spacer()
                SectionPanel(model: model)
            }
            Spacer()
        }
        .padding(Edges(top: insets.top.px, right: insets.trailing.px, bottom: Pixels(0), left: Pixels(0)))
    }
}
