import CreatorStyle
import MetalUI

/// Glass chrome for floating panels (spec §6.1, §6.6): rounded corners, a 1-pt hairline, and a fill that blurs the
/// viewport behind the panel. The fill is MetalUI's material for the panel's surface (`GlassSurface.thickness`), which
/// blurs what is drawn beneath it (MetalUI C21, gap C10-a), with the theme's `glass` role laid over it
/// (`GlassStyle.tint`: Dracula's `#21222c` at 86%, lowered a little because the material under it already hides some of
/// the backdrop). The colour stays the theme's, so the theme editor's Glass role still sets it, and Alucard's light glass
/// is light. Which material, and what the tint is, are `GlassStyle`'s (CreatorStyle); this only draws it. The blur
/// sees what MetalUI drew beneath the panel in the same window, and nothing of the desktop (MetalUI divergence 245).
/// Public so the app shell's top bar and pick banner (M6) share the chrome.
public struct GlassPanel<Body: ElementGroup>: Component {
    let surface: GlassSurface
    let body: Body
    @Environment(ThemeStore.self) var themes: ThemeStore?
    @Environment(\.accessibilityReduceTransparency) var reducesTransparency

    public init(_ surface: GlassSurface, @ElementBuilder _ body: () -> Body) {
        self.surface = surface
        self.body = body()
    }

    public var content: some ElementGroup {
        let palette = Palette(themes)
        let style = GlassStyle(themes: themes, surface: surface, reducesTransparency: reducesTransparency)
        let shape = RoundedRectangle(cornerRadius: Pixels(10))
        return ZStack(alignment: .topLeading) { body }
            .padding(Edges(all: GraphPanelLayout.glassPadding.px))
            .glassBackground(style, in: shape)
            .overlay { shape.strokeBorder(palette.hairline.color, lineWidth: Pixels(1)) }
    }
}
