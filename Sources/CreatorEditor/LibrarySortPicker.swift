import CreatorGraph
import MetalUI

/// The library's "Grouped" / "A–Z" switch: two compact buttons side by side, on the caption's row, the current order's disabled, as the panel header's dock
/// buttons are. (MetalUI's segmented `Picker` here made a skipped library draw differently from a rebuilt one,
/// `PanelContentSkipWindowTests`.)
struct LibrarySortPicker: Component {
    let model: EditorModel

    var content: some ElementGroup {
        HStack(spacing: Pixels(4)) {
            Button("Grouped") { model.setLibrarySort(.grouped) }
                .help("List each category's nodes under sub-group headings")
                .disabled(model.librarySort == .grouped)
            Button("A–Z") { model.setLibrarySort(.alphabetical) }
                .help("List each category's nodes alphabetically")
                .disabled(model.librarySort == .alphabetical)
        }
        .controlSize(.mini)
    }
}
