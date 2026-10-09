import CreatorEditor
import CreatorSketchEditor
import MetalUI

/// The context inspector, contributing the `AppKeyContext.panel` key context so the viewport's F, + and − type
/// into its number fields (gap M4-a). While a sketch is open it shows the sketch's lists instead (sketcher spec §8), in
/// chrome opaque to the pointer (`SketchChrome`).
struct InspectorDock: Component {
    let model: AppModel

    var content: some ElementGroup {
        Stack(alignment: .topLeading) {
            if let sketch = model.sketch {
                SketchChrome { SketchInspector(model: sketch.editor) }
            } else {
                InspectorPanel(model: model.editor)
            }
        }
        .keyContext(AppKeyContext.panel)
    }
}
