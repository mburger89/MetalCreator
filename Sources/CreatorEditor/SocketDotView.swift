import CreatorStyle
import MetalUI

/// One socket dot: a filled circle ringed in the panel colour. `SocketLayer` offsets it and, when it has one, gives it a tooltip.
struct SocketDotView: Component {
    let dot: SocketLayer.Dot
    let palette: Palette

    var content: some ElementGroup {
        Circle()
            .fill(dot.color.color)
            .frame(width: (2 * NodeLayout.socketRadius).px, height: (2 * NodeLayout.socketRadius).px)
            .overlay { Circle().strokeBorder(palette.panelBase.color, lineWidth: Pixels(1.5)) }
    }
}
