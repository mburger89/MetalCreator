import CreatorStyle
import MetalUI

/// The ⇧-drag box: a faint focus-colour fill (cyan in Dracula) with a focus-colour outline.
struct BoxSelectionView: Component {
    let rect: CanvasRect
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let focus = Palette(themes).focus
        return Rectangle()
            .fill(focus.opacity(0.08).color)
            .overlay { Rectangle().strokeBorder(focus.color, lineWidth: Pixels(1)) }
            .frame(width: rect.size.x.px, height: rect.size.y.px)
            .offset(x: rect.origin.x.px, y: rect.origin.y.px)
    }
}
