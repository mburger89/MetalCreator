import CreatorGeometry

/// A keyboard command the graph panel understands (spec §6.2), independent of how the key
/// arrived. `GraphKeyBindings` maps keys to these; `EditorModel.perform(_:)` runs them.
public enum GraphKeyCommand: Equatable, Sendable {
    /// Tab: the palette when the pointer is over a visible canvas, otherwise toggles the panel.
    case tab
    /// Space: the add-node palette.
    case openPalette
    case deleteSelection
    /// ⌘A: selects everything on the canvas.
    case selectAll
    /// F with the pointer over the canvas: frames the selection (everything when nothing is selected).
    case frameSelection
    /// An arrow key: nudges the selection by `delta` display canvas points (the way the arrow points on screen).
    /// `isRepeat` marks a held key's auto-repeat, which joins the undo step its first press began.
    case nudge(Vector2, isRepeat: Bool)
    case copy
    case paste
    case duplicate
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
