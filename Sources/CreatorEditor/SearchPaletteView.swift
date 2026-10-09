import CreatorStyle
import MetalUI

/// The add-node palette: a search field (focused when it opens), the matches in view, the
/// highlighted one marked, and a caption line. It is `PaletteLayout.size`, whatever it shows, so it
/// never grows or jumps. Return adds, Escape closes (keys come through `GraphPanelInput`). A press or
/// a scroll on its glass is caught here, so it never reaches the canvas, inspector or viewport beneath.
struct SearchPaletteView: Component {
    let model: EditorModel
    @FocusState var searchFocused: Bool
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let entries = model.paletteVisibleEntries
        let highlighted = model.palette?.highlighted ?? 0
        let all = model.paletteEntries
        let highlightedID = all.indices.contains(highlighted) ? all[highlighted].id : nil
        let size = PaletteLayout.size
        return ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: size.x.px, height: size.y.px)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: Pixels(0)))
                .onScrollWheel { _ in true }
            GlassPanel {
                VStack(alignment: .leading, spacing: PaletteLayout.spacing.px) {
                    TextField("Add node", text: model.palette?.query ?? "", onChange: { model.setPaletteQuery($0) })
                        .onSubmit { model.confirmPalette() }
                        .focused($searchFocused)
                        .onAppear { searchFocused = true }
                        .frame(height: PaletteLayout.fieldHeight.px)
                    VStack(alignment: .leading, spacing: Pixels(0)) {
                        ForEach(entries, id: \.id) { entry in
                            PaletteEntryRow(entry: entry, isHighlighted: entry.id == highlightedID) {
                                model.confirmPalette(entry)
                            }
                        }
                    }
                    .frame(width: PaletteLayout.contentWidth.px, height: PaletteLayout.rowsHeight.px, alignment: .topLeading)
                    Text(caption(hidden: model.paletteHiddenCount, empty: all.isEmpty))
                        .font(.caption)
                        .foregroundStyle(Palette(themes).secondaryText.color)
                        .frame(height: PaletteLayout.captionHeight.px)
                }
                .frame(width: PaletteLayout.contentSize.x.px, height: PaletteLayout.contentSize.y.px, alignment: .topLeading)
            }
        }
    }

    private func caption(hidden: Int, empty: Bool) -> String {
        if empty { return "No matching nodes" }
        return hidden > 0 ? "\(hidden) more: keep typing, or ↑ ↓" : ""
    }
}
