import CreatorEditor
import MetalUI

/// The floating add-node palette, contributing the `AppKeyContext.panel` key context so the viewport's F, + and −
/// type into its search field (gap M4-a), as they do in the graph panel and the inspector.
struct PaletteDock: Component {
    let model: AppModel

    var content: some ElementGroup {
        Stack(alignment: .topLeading) {
            SearchPaletteOverlay(model: model.editor)
        }
        .keyContext(AppKeyContext.panel)
    }
}
