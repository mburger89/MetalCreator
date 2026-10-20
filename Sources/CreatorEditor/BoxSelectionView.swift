import CreatorGraph
import CreatorStyle
import MetalUI

/// The ⇧-drag box: a faint focus-colour fill (cyan in Dracula) with a focus-colour outline.
///
/// Reads the `ThemeStore` environment and is `.equatable()` where `CanvasLayers` builds it (MetalUI C14-c, the environment
/// epoch): it is skipped while its `rect` and the theme values it read are unchanged.
struct BoxSelectionView: Component, Equatable {
    let rect: CanvasRect
    @Environment(ThemeStore.self) var themes: ThemeStore?

    /// Compares the rect only: the environment is covered by MetalUI's environment epoch, not by `==`.
    nonisolated static func == (lhs: BoxSelectionView, rhs: BoxSelectionView) -> Bool { lhs.rect == rhs.rect }

    var content: some ElementGroup {
        let focus = Palette(themes).focus
        return Rectangle()
            .fill(focus.opacity(0.08).color)
            .overlay { Rectangle().strokeBorder(focus.color, lineWidth: Pixels(1)) }
            .frame(width: rect.size.x.px, height: rect.size.y.px)
            .offset(x: rect.origin.x.px, y: rect.origin.y.px)
    }
}
