import CreatorGraph
import CreatorStyle
import MetalUI

/// One comment frame on the canvas (canvas comments spec 2026-10-09 §7): a faint accent fill with a border and a
/// title bar `CommentLayout.titleBarHeight` tall, drawn behind the wires and the nodes; thicker when selected, with
/// a resize handle then. `rect` is where it is drawn, in display canvas points. No shadows (PERF-a), few elements
/// (PERF-b).
struct CommentFrameView: Component {
    let box: CommentFrame
    let rect: CanvasRect
    let isSelected: Bool
    /// Drawn at reduced opacity: an ⌥-drag ghost.
    var isGhost = false
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        let accent = palette.accent(box.accent)
        let bar = CommentLayout.titleBar(of: CanvasRect(origin: .zero, size: rect.size))
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(accent.opacity(0.12).color)
            HStack(spacing: Pixels(0)) {
                Text(box.title)
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(palette.primaryText.color)
                Spacer()
            }
            .padding(Edges(top: Pixels(0), right: Pixels(8), bottom: Pixels(0), left: Pixels(8)))
            .frame(width: bar.size.x.px, height: bar.size.y.px, alignment: .leading)
            .background(accent.opacity(0.35).color)
            .clipped()
            Rectangle().strokeBorder(isSelected ? accent.color : accent.opacity(0.6).color,
                                     lineWidth: Pixels(isSelected ? 2 : 1))
            if isSelected { CommentHandleView(size: rect) }
        }
        .frame(width: rect.size.x.px, height: rect.size.y.px, alignment: .topLeading)
        .opacity(isGhost ? 0.4 : 1)
        .offset(x: rect.origin.x.px, y: rect.origin.y.px)
    }
}
