import MetalUI

/// One palette match (`PaletteEntryLabel`); clicking adds it.
struct PaletteEntryRow: Component {
    let entry: PaletteEntry
    let isHighlighted: Bool
    let action: @MainActor () -> Void

    var content: some ElementGroup {
        Button(action: action) {
            PaletteEntryLabel(entry: entry, isHighlighted: isHighlighted)
        }
        .buttonStyle(.plain)
    }
}
