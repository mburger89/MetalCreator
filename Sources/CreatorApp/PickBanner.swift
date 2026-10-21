import CreatorEditor
import CreatorStyle
import MetalUI

/// "Pick edges in view…" in progress: what to do, how many are picked (in the selection colour, pink in Dracula),
/// Cancel (Escape) and Done (Return). While a face is picked for a lattice's Face mapping (`isFace`) one click ends it, so there is
/// only what to do and Cancel.
struct PickBanner: Component {
    let model: AppModel
    let picked: Int
    var isFace = false
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        GlassPanel(.pickBanner) {
            HStack(spacing: Pixels(10)) {
                Text(isFace ? "Click a face of the part to map the lattice to it" : "Click edges to pick them · \(picked) picked")
                    .font(.callout)
                    .foregroundStyle(Palette(themes).selection.color)
                Button("Cancel") { model.cancelPick() }
                    .keyboardShortcut(.escape, modifiers: [])
                if !isFace {
                    Button("Done") { model.finishPick() }
                        .keyboardShortcut(.return, modifiers: [])
                }
            }
        }
    }
}
