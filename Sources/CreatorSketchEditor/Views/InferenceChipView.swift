import CreatorStyle
import MetalUI

/// The inferred constraints' chip framed where `InferenceChip` places it: their names in the selection's green on the
/// theme's glass, so it reads as a hint about the geometry rather than a measurement.
struct InferenceChipView: Component {
    let chip: InferenceChip
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let colors = SketchColors(themes)
        let shape = RoundedRectangle(cornerRadius: Pixels(6))
        return ProposalText(chip.text)
            .font(.caption)
            .foregroundStyle(colors.inferred)
            .frame(width: Pixels(Float(chip.size.width)), height: Pixels(Float(chip.size.height)))
            .background(colors.glass, in: shape)
            .overlay { shape.strokeBorder(colors.hairline, lineWidth: Pixels(1)) }
            .offset(x: Pixels(Float(chip.origin.x)), y: Pixels(Float(chip.origin.y)))
    }
}
