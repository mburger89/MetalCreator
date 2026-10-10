import CreatorStyle
import MetalUI

/// Glass chrome for floating panels (spec §6.1, §6.6): the theme's glass fill (`#21222c` at 86% in Dracula), its 1-pt
/// hairline (`#ffffff1f`) and rounded corners. The fill stays the theme's own flat tint, on purpose (gap M5-c, decided
/// with MetalUI C10 in hand): MetalUI's materials (`.ultraThinMaterial` and the rest) are a flat grey fitted to
/// SwiftUI's, with no backdrop blur and no theme, so they would drop the theme's `glass` role (which the theme editor
/// lets people set) for a grey no theme chose; and `.blur(radius:)` blurs a view's own pixels, not what is behind it.
/// A true backdrop blur is MetalUI's C10-c (docs/metalui-gaps.md C10-a), and the viewport behind the panels is a GPU
/// surface a CPU blur could not read anyway. Public so the app shell's top bar and pick banner (M6) share the chrome.
public struct GlassPanel<Body: ElementGroup>: Component {
    let body: Body
    @Environment(ThemeStore.self) var themes: ThemeStore?

    public init(@ElementBuilder _ body: () -> Body) {
        self.body = body()
    }

    public var content: some ElementGroup {
        let palette = Palette(themes)
        let shape = RoundedRectangle(cornerRadius: Pixels(10))
        return ZStack(alignment: .topLeading) { body }
            .padding(Edges(all: GraphPanelLayout.glassPadding.px))
            .background(palette.glass.color, in: shape)
            .overlay { shape.strokeBorder(palette.hairline.color, lineWidth: Pixels(1)) }
    }
}
