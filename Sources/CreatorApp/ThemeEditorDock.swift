import MetalUI

/// The theme editor (Themes milestone), floating at the window's top-right corner below the top bar, over the
/// inspector and down to `bottom` points from the window's bottom edge (above a graph panel docked at the bottom,
/// `ThemeEditorLayout.bottom(dock:panelHeight:)`), so the graph panel and the viewport show each change as it is made. Drawn over everything else in
/// the window (`AppWindowRoot`); nothing while it is closed. It contributes the `AppKeyContext.panel` key context,
/// so the viewport's F, + and − type into its name field (gap M4-a), as they do in the other panels.
struct ThemeEditorDock: Component {
    let model: ThemeEditorModel
    /// The panel's distance from the window's bottom edge.
    let bottom: Double

    var content: some ElementGroup {
        Stack(alignment: .topTrailing) {
            if model.isOpen {
                ZStack(alignment: .topTrailing) { ThemeEditorPanel(model: model) }
                    .padding(Edges(top: ThemeEditorLayout.top.px, right: AppLayout.margin.px, bottom: bottom.px,
                                   left: Pixels(0)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .keyContext(AppKeyContext.panel)
    }
}
