import CreatorStyle
import MetalUI

/// The window background (spec §6.6): the theme's `backgroundTop` fading to its `backgroundBottom`, top to bottom
/// (`#3a3d4e` to `#191a21` in Dracula), as MetalUI's `LinearGradient` (gap M5-d). A vertical gradient on an upright
/// rectangle is MetalUI's cheap case, one pixel wide, so it costs nothing to redraw as the window resizes. The app's
/// viewport paints the same two colours on the GPU behind its scene (`ViewportRenderer`), so the app shell doesn't
/// use this; the preview window (`GraphPanelPreview`) does.
public struct WindowBackground: Component {
    @Environment(ThemeStore.self) var themes: ThemeStore?

    public init() {}

    public var content: some ElementGroup {
        let palette = Palette(themes)
        return LinearGradient(colors: [palette.backgroundTop.color, palette.backgroundBottom.color],
                              startPoint: .top, endPoint: .bottom)
    }
}
