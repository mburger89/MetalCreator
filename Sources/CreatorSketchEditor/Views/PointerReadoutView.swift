import CreatorStyle
import MetalUI

/// The pointer readout's chip (`SketchEditorModel.readoutChip`), framed where the model places it: the theme's glass
/// with its hairline, no shadow, and never in the pointer's way. The host draws it over the viewport, whose points
/// are the window's. This is glue; the text and the placement are the model's.
public struct PointerReadoutView: Component {
    let model: SketchEditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    public init(model: SketchEditorModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        let colors = SketchColors(themes)
        let shape = RoundedRectangle(cornerRadius: Pixels(6))
        ZStack(alignment: .topLeading) {
            if let chip = model.readoutChip {
                ProposalText(chip.text)
                    .font(.caption)
                    .foregroundStyle(colors.primary)
                    .frame(width: Pixels(Float(chip.size.width)), height: Pixels(Float(chip.size.height)))
                    .background(colors.glass, in: shape)
                    .overlay { shape.strokeBorder(colors.hairline, lineWidth: Pixels(1)) }
                    .offset(x: Pixels(Float(chip.origin.x)), y: Pixels(Float(chip.origin.y)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
