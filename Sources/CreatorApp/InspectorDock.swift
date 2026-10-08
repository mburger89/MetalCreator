import CreatorEditor
import MetalUI

/// The context inspector, contributing the `AppKeyContext.panel` key context so the viewport's F, + and − type
/// into its number fields (gap M4-a).
struct InspectorDock: Component {
    let model: AppModel

    var content: some ElementGroup {
        Stack(alignment: .topLeading) {
            InspectorPanel(model: model.editor)
        }
        .keyContext(AppKeyContext.panel)
    }
}
