import MetalUI

/// One row of the node library: a category's coloured header, or a type (or, in the "Groups" section, a group
/// definition, with Delete when no node uses it). A type's row shows the palette's row
/// content (`PaletteEntryLabel`) under one gesture, `GraphPanelInput.libraryGesture(for:)`: a click adds the type at
/// the visible canvas's centre, a drag carries it to the canvas. Not a `Button`, because a child's click holds off an
/// enclosing drag for the whole press in MetalUI (as in SwiftUI). Its help is the type's inputs → outputs.
struct LibraryRow: Component {
    let model: EditorModel
    let input: GraphPanelInput
    let item: LibraryItem

    var content: some ElementGroup {
        if let group = item.group {
            // A group definition: a click or drag places an instance; one nothing uses can be deleted (a button beside
            // the gesture's area, so its click isn't a library click).
            HStack(spacing: Pixels(4)) {
                ZStack(alignment: .topLeading) {
                    PaletteEntryLabel(entry: group.paletteEntry, isHighlighted: false)
                }
                .gesture(input.libraryGesture(for: group.key))
                .contentShape(Rectangle())
                .help(model.librarySummary(of: group.key) ?? group.name)
                if group.canDelete {
                    Button("Delete") { model.deleteGroup(group.group) }
                        .help("Delete this group: no node uses it")
                }
            }
        } else if item.isGroupsHeader {
            LibrarySectionHeader(category: .feature, title: "Groups", accent: .purple)
        } else if let entry = item.entry {
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
