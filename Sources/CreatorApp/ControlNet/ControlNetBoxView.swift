import CreatorEditor
import CreatorStyle
import MetalUI

/// The box being dragged over the net (`ControlNetSession.boxRect`, in the viewport's points, which are the window's): a faint
/// focus-colour fill with an outline, placed as `PointerReadoutView` is. It never takes the pointer.
struct ControlNetBoxView: Component {
    let session: ControlNetSession
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let focus = Palette(themes).focus
        return ZStack(alignment: .topLeading) {
            if let rect = session.boxRect {
                Rectangle()
                    .fill(focus.opacity(0.08).color)
                    .overlay { Rectangle().strokeBorder(focus.color, lineWidth: Pixels(1)) }
                    .frame(width: Pixels(Float(rect.maxX - rect.minX)), height: Pixels(Float(rect.maxY - rect.minY)))
                    .offset(x: Pixels(Float(rect.minX)), y: Pixels(Float(rect.minY)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
