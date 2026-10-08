import CreatorEditor
import MetalUI

/// The graph panel in its dock with its resize handle, and the inspector on the right (spec §6.1). Hidden, the
/// panel leaves "Show graph" at the bottom left (Tab is its shortcut).
struct PanelArea: Component {
    let model: AppModel

    var content: some ElementGroup {
        switch model.editor.dock {
        case .left:
            HStack(alignment: .top, spacing: Pixels(0)) {
                ZStack { GraphDock(model: model) }
                    .frame(width: model.panelWidth.px)
                    .frame(maxHeight: .infinity)
                ZStack { PanelResizeHandle(model: model, alongWidth: true) }
                    .frame(width: AppLayout.resizeHandle.px)
                    .frame(maxHeight: .infinity)
                Spacer()
                InspectorDock(model: model)
            }
        case .bottom:
            VStack(alignment: .leading, spacing: Pixels(0)) {
                HStack(alignment: .top) {
                    Spacer()
                    InspectorDock(model: model)
                }
                Spacer()
                ZStack { PanelResizeHandle(model: model, alongWidth: false) }
                    .frame(height: AppLayout.resizeHandle.px)
                    .frame(maxWidth: .infinity)
                ZStack { GraphDock(model: model) }
                    .frame(height: model.panelHeight.px)
                    .frame(maxWidth: .infinity)
            }
        case .hidden:
            VStack(alignment: .leading, spacing: Pixels(0)) {
                HStack(alignment: .top) {
                    Spacer()
                    InspectorDock(model: model)
                }
                Spacer()
                GraphShowButton(model: model.editor)
            }
        }
    }
}
