import CreatorEditor
import CreatorStyle
import MetalUI

/// A role's colour as a small rounded swatch with the glass hairline around it.
struct ThemeSwatch: Component {
    let colour: HexColor
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let shape = RoundedRectangle(cornerRadius: Pixels(4))
        return Color.clear
            .frame(width: ThemeEditorLayout.swatchWidth.px, height: ThemeEditorLayout.swatchHeight.px)
            .background(colour.color, in: shape)
            .overlay { shape.strokeBorder(Palette(themes).hairline.color, lineWidth: Pixels(1)) }
    }
}
