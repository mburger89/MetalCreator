import CreatorEditor
import CreatorStyle
import MetalUI

/// "Pick edges in view…" in progress: what to do, how many are picked (in the selection colour, pink in Dracula),
/// Cancel (Escape) and Done (Return).
struct PickBanner: Component {
    let model: AppModel
    let picked: Int
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        GlassPanel {
            HStack(spacing: Pixels(10)) {
                Text("Click edges to pick them · \(picked) picked")
                    .font(.callout)
                    .foregroundStyle(Palette(themes).selection.color)
                Button("Cancel") { model.cancelPick() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Done") { model.finishPick() }
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
    }
}
