import CreatorDrawingEditor
import CreatorStyle
import MetalUI

/// The model area in Drawing mode (plan R28): the sheet canvas in place of the viewport, with the sheet tabs under it, both inside
/// the part of the window the panels leave uncovered (`AppLayout.modelArea`). The surround fills the whole window, so the glass
/// panels that float over the viewport float over it the same way.
struct DrawingDock: Component {
    let model: AppModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    /// The tab row's height, with its padding.
    static let tabsHeight = 36.0

    var content: some ElementGroup {
        let editor = model.drawing.editor
        let area = AppLayout.modelArea(dock: model.editor.dock, panelWidth: model.panelWidth, panelHeight: model.panelHeight)
        let surround = (themes?.current ?? .dracula).colors.backgroundBottom
        ZStack(alignment: .topLeading) {
            surround.color.frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: Pixels(0)) {
                SheetCanvas(model: editor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: Pixels(0)) {
                    SheetTabs(model: editor)
                    Spacer()
                }
                .padding(Edges(top: Pixels(6), right: Pixels(0), bottom: Pixels(0), left: Pixels(0)))
                .frame(height: Pixels(Float(Self.tabsHeight)))
                // A tab's rename field must keep its keys: the viewport's and the sheet's must not take them.
                .keyContext(AppKeyContext.panel)
            }
            .padding(Edges(top: area.top.px, right: area.trailing.px, bottom: area.bottom.px, left: area.leading.px))
        }
    }
}
