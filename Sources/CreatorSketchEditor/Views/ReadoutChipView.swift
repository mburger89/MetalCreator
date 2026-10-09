import CreatorStyle
import MetalUI

/// One readout chip framed where `ReadoutChip` places it: its text centred in the theme's glass with its hairline,
/// no shadow.
struct ReadoutChipView: Component {
    let chip: ReadoutChip
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let colors = SketchColors(themes)
        let shape = RoundedRectangle(cornerRadius: Pixels(6))
        return ProposalText(chip.text)
            .font(.caption)
            .foregroundStyle(colors.primary)
            .frame(width: Pixels(Float(chip.size.width)), height: Pixels(Float(chip.size.height)))
            .background(colors.glass, in: shape)
            .overlay { shape.strokeBorder(colors.hairline, lineWidth: Pixels(1)) }
            .offset(x: Pixels(Float(chip.origin.x)), y: Pixels(Float(chip.origin.y)))
    }
}
