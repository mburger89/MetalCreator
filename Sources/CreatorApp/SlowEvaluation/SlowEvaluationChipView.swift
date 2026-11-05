import CreatorEditor
import CreatorStyle
import MetalUI

/// The chip over the viewport while an evaluation runs long: MetalUI's spinner and "Building Fillet…". All behaviour is
/// `SlowEvaluationModel`'s; this only draws its `text`. It is transient, so it takes no pointer: a click where it appeared reaches the viewport.
struct SlowEvaluationChipView: Component {
    let model: AppModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        if let text = model.slowEvaluation.text {
            GlassPanel(.chip, takesPointer: false) {
                HStack(spacing: Pixels(6)) {
                    ProgressView().controlSize(.small)
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(Palette(themes).primaryText.color)
                }
            }
        }
    }
}
