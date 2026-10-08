import MetalUI

/// One anchor grid cell: filled purple when selected.
struct AnchorCell: Component {
    let isSelected: Bool
    let action: @MainActor () -> Void

    var content: some ElementGroup {
        Button(action: action) {
            Circle()
                .fill(isSelected ? Palette.primaryButton.color : Palette.field.color)
                .frame(width: Pixels(10), height: Pixels(10))
        }
        .buttonStyle(.plain)
    }
}
