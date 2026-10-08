extension EditorModel {
    /// Runs a keyboard command. Returns false when it does nothing here, so the key can go on.
    @discardableResult
    public func perform(_ command: GraphKeyCommand) -> Bool {
        switch command {
        case .tab:
            if isPanelVisible, pointerLocation != nil { openPalette() } else { toggleHidden() }
        case .openPalette:
            guard isPanelVisible else { return false }
            openPalette()
        case .deleteSelection:
            guard !selection.isEmpty else { return false }
            deleteSelection()
        case .copy, .paste, .duplicate, .zoomIn, .zoomOut, .undo, .redo:
            performEdit(command)
        case .cancel, .paletteUp, .paletteDown, .paletteConfirm:
            return performPaletteCommand(command)
        }
        return true
    }

    /// The commands that always apply: clipboard, zoom and undo.
    private func performEdit(_ command: GraphKeyCommand) {
        switch command {
        case .copy: copySelection()
        case .paste: paste()
        case .duplicate: duplicateSelection()
        case .zoomIn: zoom(in: true)
        case .zoomOut: zoom(in: false)
        case .undo: document.undo()
        case .redo: document.redo()
        default: break // `perform(_:)` routes every other command elsewhere.
        }
    }

    /// The palette's keys. Escape does nothing (and goes on) while no palette is open.
    private func performPaletteCommand(_ command: GraphKeyCommand) -> Bool {
        switch command {
        case .cancel:
            guard palette != nil else { return false }
            closePalette()
        case .paletteUp: movePaletteHighlight(by: -1)
        case .paletteDown: movePaletteHighlight(by: 1)
        case .paletteConfirm: confirmPalette()
        default: return false // `perform(_:)` routes every other command elsewhere.
        }
        return true
    }
}
