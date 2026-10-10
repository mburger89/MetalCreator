/// A keyboard command the graph panel understands (spec §6.2), independent of how the key
/// arrived. `GraphKeyBindings` maps keys to these; `EditorModel.perform(_:)` runs them.
public enum GraphKeyCommand: Equatable, Sendable {
    /// Tab: the palette when the pointer is over a visible canvas, otherwise toggles the panel.
    case tab
    /// Space: the add-node palette.
    case openPalette
    case deleteSelection
    case copy
    case paste
    case duplicate
    /// ⌘G: groups the selection (groups spec §5).
    case group
    /// ⇧⌘G: ungroups the selected group node.
    case ungroup
    case zoomIn
    case zoomOut
    case undo
    case redo
    /// Escape: closes the palette, cancels a drag-free state.
    case cancel
    case paletteUp
    case paletteDown
    case paletteConfirm
}
