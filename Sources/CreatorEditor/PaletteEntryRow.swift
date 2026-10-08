import MetalUI

/// One palette match: a category-coloured dot and the type's name; clicking adds it.
struct PaletteEntryRow: Component {
    let entry: PaletteEntry
    let isHighlighted: Bool
    let action: @MainActor () -> Void

    var content: some ElementGroup {
        Button(action: action) {
            HStack(spacing: Pixels(6)) {
                Circle().fill(Palette.header(for: entry.category).color).frame(width: Pixels(8), height: Pixels(8))
                Text(entry.displayName).font(.callout).foregroundStyle(Palette.primaryText.color)
                Spacer()
            }
            .padding(Edges(top: Pixels(3), right: Pixels(6), bottom: Pixels(3), left: Pixels(6)))
            .background(isHighlighted ? Palette.field.color : Color.clear, in: RoundedRectangle(cornerRadius: Pixels(4)))
        }
        .buttonStyle(.plain)
    }
}
