import CreatorEditor
import MetalUI

/// The graph panel, contributing the `AppKeyContext.panel` key context so the viewport's F, + and − type into
/// its palette's search field (gap M4-a).
struct GraphDock: Component {
    let model: AppModel

    var content: some ElementGroup {
        Stack(alignment: .topLeading) {
            ZStack { GraphPanel(model: model.editor, input: model.graphInput) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .keyContext(AppKeyContext.panel)
    }
}
