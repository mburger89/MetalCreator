import CreatorGraph
import CreatorStyle
import MetalUI

/// The resize handle of a selected comment: a small square in the focus colour over its bottom-right corner, placed
/// by `CommentLayout.handle(of:)` so drawing and the hit test agree.
struct CommentHandleView: Component {
    let size: CanvasRect
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let handle = CommentLayout.handle(of: CanvasRect(origin: .zero, size: size.size))
        return Rectangle()
            .fill(Palette(themes).focus.color)
            .frame(width: handle.size.x.px, height: handle.size.y.px)
            .offset(x: handle.origin.x.px, y: handle.origin.y.px)
    }
}
