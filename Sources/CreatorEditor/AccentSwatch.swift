import CreatorGraph
import CreatorStyle
import MetalUI

/// One accent in `AccentPicker`: a disc in the theme's colour for the role, ringed when it is the chosen one.
struct AccentSwatch: Component {
    let role: AccentRole
    let isSelected: Bool
    let action: @MainActor () -> Void
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        return Button(action: action) {
            Circle()
                .fill(palette.accent(role).color)
                .frame(width: Pixels(14), height: Pixels(14))
                .overlay {
                    Circle().strokeBorder(isSelected ? palette.primaryText.color : Color.clear, lineWidth: Pixels(2))
                }
        }
        .buttonStyle(.plain)
    }
}
