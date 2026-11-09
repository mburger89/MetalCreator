import CreatorEditor
import CreatorStyle
import MetalUI

/// The "AI connected" chip at the viewport's lower right, one row above the slow-evaluation chip (`AppLayout.aiConnectedInsets`),
/// while a client is connected. It takes no pointer.
struct AIConnectedDock: Component {
    let model: AppModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let insets = AppLayout.aiConnectedInsets(dock: model.editor.dock, panelWidth: model.panelWidth, panelHeight: model.panelHeight)
        VStack(alignment: .trailing, spacing: Pixels(0)) {
            Spacer()
            HStack(spacing: Pixels(0)) {
                Spacer()
                if model.mcp?.isClientConnected == true {
                    GlassPanel(.chip, takesPointer: false) {
                        Text("AI connected")
                            .font(.caption)
                            .foregroundStyle(Palette(themes).primaryText.color)
                    }
                }
            }
        }
        .padding(Edges(top: Pixels(0), right: insets.trailing.px, bottom: insets.bottom.px, left: Pixels(0)))
    }
}
