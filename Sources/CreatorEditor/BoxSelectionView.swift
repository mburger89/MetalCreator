import MetalUI

/// The ⇧-drag box: a faint cyan fill with a cyan outline.
struct BoxSelectionView: Component {
    let rect: CanvasRect

    var content: some ElementGroup {
        Rectangle()
            .fill(Palette.focus.opacity(0.08).color)
            .overlay { Rectangle().strokeBorder(Palette.focus.color, lineWidth: Pixels(1)) }
            .frame(width: rect.size.x.px, height: rect.size.y.px)
            .offset(x: rect.origin.x.px, y: rect.origin.y.px)
    }
}
