import CreatorEditor
import CreatorStyle
import MetalUI

/// What fills the viewport's place where the 3D view cannot draw (Linux and Windows in xp-1: its renderer is Metal, and
/// the SDL one is xp-3): the theme's window background and a centred glass card saying so. The layout, split, top bar and
/// panels around it are the same as on macOS.
struct ViewportPlaceholder: Component {
    /// The card's sentence (cross-platform spec §2.3).
    static let message = "The 3D view isn't available on this platform yet."

    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        ZStack {
            WindowBackground()
            GlassPanel(.fieldLegend) {
                Text(Self.message)
                    .font(.callout)
                    .foregroundStyle(Palette(themes).secondaryText.color)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
