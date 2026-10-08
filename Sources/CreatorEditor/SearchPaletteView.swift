import MetalUI

/// The add-node palette: a search field (focused when it opens) and the matching types, the
/// highlighted one marked. Return adds it, Escape closes (keys come through `GraphPanelInput`).
struct SearchPaletteView: Component {
    let model: EditorModel
    @FocusState var searchFocused: Bool

    var content: some ElementGroup {
        let entries = model.paletteEntries
        let highlightedID = entries.indices.contains(model.palette?.highlighted ?? 0)
            ? entries[model.palette?.highlighted ?? 0].id : nil
        return GlassPanel {
            VStack(alignment: .leading, spacing: Pixels(4)) {
                TextField("Add node", text: model.palette?.query ?? "", onChange: { model.setPaletteQuery($0) })
                    .onSubmit { model.confirmPalette() }
                    .focused($searchFocused)
                    .onAppear { searchFocused = true }
                ForEach(entries, id: \.id) { entry in
                    PaletteEntryRow(entry: entry, isHighlighted: entry.id == highlightedID) {
                        model.confirmPalette(entry)
                    }
                }
                if entries.isEmpty {
                    Text("No matching nodes").font(.caption).foregroundStyle(Palette.secondaryText.color)
                }
            }
            .frame(width: Pixels(220), alignment: .topLeading)
        }
    }
}
