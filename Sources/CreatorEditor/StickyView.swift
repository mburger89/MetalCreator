import CreatorGraph
import CreatorStyle
import MetalUI

/// One sticky note on the canvas (canvas comments spec 2026-10-09 §7): a card tinted with its accent, its text
/// wrapped inside 8 points of padding, a ring in the accent when selected and a resize handle then. `rect` is where
/// it is drawn, in display canvas points. No shadows (docs/metalui-gaps.md PERF-a) and few elements (PERF-b).
struct StickyView: Component {
    let note: StickyNote
    let rect: CanvasRect
    let isSelected: Bool
    /// Drawn at reduced opacity: an ⌥-drag ghost.
    var isGhost = false
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        let accent = palette.accent(note.accent)
        let pad = CommentLayout.notePadding.px
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(accent.opacity(0.22).color)
            Text(note.text)
                .font(.callout)
                .foregroundStyle(palette.primaryText.color)
                .padding(pad)
                .frame(width: rect.size.x.px, height: rect.size.y.px, alignment: .topLeading)
                .clipped()
            Rectangle().strokeBorder(isSelected ? accent.color : accent.opacity(0.5).color,
                                     lineWidth: Pixels(isSelected ? 2 : 1))
            if isSelected { CommentHandleView(size: rect) }
        }
        .frame(width: rect.size.x.px, height: rect.size.y.px, alignment: .topLeading)
        .opacity(isGhost ? 0.4 : 1)
        .offset(x: rect.origin.x.px, y: rect.origin.y.px)
    }
}
