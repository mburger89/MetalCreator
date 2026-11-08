import CreatorGraph
import MetalUI

/// The library's "Grouped" / "A–Z" switch: a compact segmented `Picker` on the caption's row. (Until MetalUI #240 and #242 a
/// skipped library drew a segmented `Picker` differently from a rebuilt one, so this was two buttons;
/// `PanelContentSkipWindowTests` holds it to the same drawing now.)
struct LibrarySortPicker: Component {
    let model: EditorModel

    var content: some ElementGroup {
        Picker("Sort", selection: Binding(get: { model.librarySort }, set: { model.setLibrarySort($0) })) {
            Text("Grouped").tag(LibrarySort.grouped)
            Text("A–Z").tag(LibrarySort.alphabetical)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.mini)
        .help("Order the library's nodes: grouped under sub-group headings, or alphabetically")
    }
}
