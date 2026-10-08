import CreatorStyle
import MetalUI

/// An inspector row: a label in primary text, then the row's controls.
struct LabeledRow<Controls: ElementGroup>: Component {
    let label: String
    let controls: Controls
    @Environment(ThemeStore.self) var themes: ThemeStore?

    init(label: String, @ElementBuilder controls: () -> Controls) {
        self.label = label
        self.controls = controls()
    }

    var content: some ElementGroup {
        HStack(spacing: Pixels(8)) {
            Text(label).font(.callout).foregroundStyle(Palette(themes).primaryText.color)
            controls
        }
    }
}
