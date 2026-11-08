import MetalUI

/// Puts the section panel, and the Measure panel under it (8 points apart), at the viewport's upper right, under the top bar and clear of the docked panels
/// (`AppLayout.sectionPanelInsets`). It fills the window so the card can stand in a corner; only the card itself is drawn.
struct SectionPanelDock: Component {
    let model: AppModel
    /// Whether the theme editor floats over the inspector column; the panel then stands left of it.
    let themeEditorOpen: Bool

    var content: some ElementGroup {
        let insets = AppLayout.sectionPanelInsets(dock: model.editor.dock, panelWidth: model.panelWidth, panelHeight: model.panelHeight,
                                                themeEditorOpen: themeEditorOpen)
        let gaps = Self.gaps(sectionOn: model.document.section?.isOn == true,
                             measureShows: model.showsMeasurePanel,
                             zebraShows: model.showsZebra)
        VStack(alignment: .trailing, spacing: Pixels(0)) {
            HStack(spacing: Pixels(0)) {
                Spacer()
                SectionPanel(model: model)
            }
            HStack(spacing: Pixels(0)) {
                Spacer()
                MeasurePanel(model: model)
            }
            .padding(Edges(top: gaps.measure.px,
                           right: Pixels(0), bottom: Pixels(0), left: Pixels(0)))
            HStack(spacing: Pixels(0)) {
                Spacer()
                ZebraPanel(model: model)
            }
            .padding(Edges(top: gaps.zebra.px, right: Pixels(0), bottom: Pixels(0), left: Pixels(0)))
            Spacer()
        }
        .padding(Edges(top: insets.top.px, right: insets.trailing.px, bottom: Pixels(0), left: Pixels(0)))
        // Typing in the Offset field must not reach the viewport's F, + and − keys.
        .keyContext(AppKeyContext.panel)
    }

    /// The 8-point gap above the Measure and Zebra rows: only when a panel above shows.
    static func gaps(sectionOn: Bool, measureShows: Bool, zebraShows: Bool) -> (measure: Double, zebra: Double) {
        (sectionOn && measureShows ? 8 : 0, zebraShows && (sectionOn || measureShows) ? 8 : 0)
    }
}

extension AppModel {
    /// Whether any card of the section dock (Section, Measure, Zebra) shows now.
    var showsSectionCards: Bool {
        (document.section?.isOn == true && sketch == nil) || showsMeasurePanel || showsZebra
    }
}
