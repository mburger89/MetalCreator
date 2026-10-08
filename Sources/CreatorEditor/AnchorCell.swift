import CreatorStyle
import MetalUI

/// One anchor grid cell: filled in the primary-button colour (purple in Dracula) when selected.
struct AnchorCell: Component {
    let isSelected: Bool
    let action: @MainActor () -> Void
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        return Button(action: action) {
            Circle()
                .fill(isSelected ? palette.primaryButton.color : palette.field.color)
                .frame(width: Pixels(10), height: Pixels(10))
        }
        .buttonStyle(.plain)
    }
}
