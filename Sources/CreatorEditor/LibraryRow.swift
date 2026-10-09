import MetalUI

/// One row of the node library: a category's coloured header, or a type. A type's row shows the palette's row
/// content (`PaletteEntryLabel`) under one gesture, `GraphPanelInput.libraryGesture(for:)`: a click adds the type at
/// the visible canvas's centre, a drag carries it to the canvas. Not a `Button`, because a child's click holds off an
/// enclosing drag for the whole press in MetalUI (as in SwiftUI). Its help is the type's inputs → outputs.
struct LibraryRow: Component {
    let model: EditorModel
    let input: GraphPanelInput
    let item: LibraryItem

    var content: some ElementGroup {
        if let entry = item.entry {
            ZStack(alignment: .topLeading) {
                PaletteEntryLabel(entry: entry, isHighlighted: false)
            }
            .gesture(input.libraryGesture(for: entry.typeID))
            .contentShape(Rectangle())
            .help(model.librarySummary(of: entry.typeID) ?? entry.displayName)
        } else {
            LibrarySectionHeader(category: item.category, title: LibrarySection.title(for: item.category))
        }
    }
}
