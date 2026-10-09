import CreatorStyle
import MetalUI

/// Glass chrome for floating panels (spec §6.1, §6.6): the theme's glass fill (`#21222c` at 86% in
/// Dracula), its 1-pt hairline (`#ffffff1f`) and rounded corners. The background blur is a MetalUI
/// gap (materials and `.blur` are not offered; docs/metalui-gaps.md), so the panel is translucent
/// without blur. Public so the app shell's top bar and pick banner (M6) share the chrome.
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
