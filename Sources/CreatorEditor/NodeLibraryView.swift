import CreatorStyle
import MetalUI

/// The node library: a "Nodes" caption and a search field over the registry's types grouped by category, each group
/// under a header in its category's colour. Click a type to add it at the visible canvas's centre; drag it onto the
/// canvas to add it there; hover it for its inputs → outputs. Kept cheap for MetalUI's whole-window rebuilds
/// (docs/metalui-gaps.md PERF-b): one windowed `List` of uniform rows (only those in view are built), flat fills,
/// no shadows, rows keyed by type.
struct NodeLibraryView: Component {
    let model: EditorModel
    let input: GraphPanelInput
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        let rows = model.libraryItems
        return VStack(alignment: .leading, spacing: PaletteLayout.spacing.px) {
            Text("Nodes")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(palette.secondaryText.color)
                .frame(height: PaletteLayout.captionHeight.px)
            TextField("Search nodes", text: model.libraryQuery, onChange: { model.setLibraryQuery($0) })
                .frame(height: PaletteLayout.fieldHeight.px)
            if rows.isEmpty {
                Text("No matching nodes").font(.caption).foregroundStyle(palette.secondaryText.color)
            }
            ScrollView {
                List(rows, rowHeight: PaletteLayout.rowHeight.px) { row in
                    ZStack(alignment: .topLeading) { LibraryRow(model: model, input: input, item: row) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(Edges(all: Pixels(6)))
        .background(palette.panelBase.color, in: RoundedRectangle(cornerRadius: Pixels(6)))
    }
}
