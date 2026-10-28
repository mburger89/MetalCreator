import CreatorEditor
import CreatorStyle
import MetalUI

/// The model dimension tool in progress: what to do and how many are picked (in the selection colour), the chip saying why a
/// pair added nothing, and Cancel (Escape). It takes `PickBanner`'s place.
struct ModelDimensionBanner: Component {
    let model: AppModel
    let session: ModelDimensionSession
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        GlassPanel(.pickBanner) {
            VStack(spacing: Pixels(4)) {
                HStack(spacing: Pixels(10)) {
                    Text(ModelDimensionText.prompt(picked: session.pickedCount))
                        .font(.callout)
                        .foregroundStyle(Palette(themes).selection.color)
                    Button("Cancel") { model.cancelModelDimension() }
                        .keyboardShortcut(.escape, modifiers: [])
                }
                if let message = session.message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(Palette(themes).theme.colors.sketchConflicting.color)
                }
            }
        }
    }
}
