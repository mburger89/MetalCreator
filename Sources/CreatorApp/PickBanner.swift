import CreatorEditor
import CreatorStyle
import MetalUI

/// "Pick edges in view…" in progress: what to do, how many are picked (in the selection colour, pink in Dracula),
/// Cancel (Escape) and Done (Return). While a face is picked (for a lattice's Face mapping or a loft's end: `prompt` is not
/// `.edges`) one click ends it, so there is only what to do and Cancel.
struct PickBanner: Component {
    let model: AppModel
    let picked: Int
    var prompt = PickSession.Prompt.edges
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        GlassPanel(.pickBanner) {
            HStack(spacing: Pixels(10)) {
                Text(prompt.text(picked: picked))
                    .font(.callout)
                    .foregroundStyle(Palette(themes).selection.color)
                Button("Cancel") { model.cancelPick() }
                    .keyboardShortcut(.escape, modifiers: [])
                if prompt == .edges {
                    Button("Done") { model.finishPick() }
                        .keyboardShortcut(.return, modifiers: [])
                }
            }
        }
    }
}
