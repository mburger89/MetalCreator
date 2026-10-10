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
            guard !canvasSelection.isEmpty else { return false }
            deleteSelection()
        case .selectAll, .nudge, .frameSelection, .cut, .addNote, .addFrame:
            return performSelectionCommand(command)
        case .group, .ungroup:
            return performGroupKey(command)
        case .copy, .paste, .duplicate, .zoomIn, .zoomOut, .undo, .redo:
            performEdit(command)
        case .cancel, .paletteUp, .paletteDown, .paletteConfirm:
            return performPaletteCommand(command)
        }
        return true
    }

    /// The selection's keys (spec 2026-10-09 §3), and ⌘X. They act only while the panel shows the canvas: with it hidden they
    /// would select, move or cut nodes no one can see. During a drag they are claimed and do nothing, as Esc is during a
    /// move: a nudge or a selection change would end the move's coalescing and split it into two undo steps, and F
    /// would shift the canvas under the pointer.
    private func performSelectionCommand(_ command: GraphKeyCommand) -> Bool {
        guard isPanelVisible else { return false }
        guard interaction == nil else { return true }
        switch command {
        case .selectAll: selectAll()
        case .nudge(let delta, let isRepeat): return nudgeSelection(by: delta, isRepeat: isRepeat)
        case .frameSelection: return pointerLocation != nil && frameSelection()
        case .cut:
            guard !canvasSelection.isEmpty else { return false }
            cutSelection()
        case .addNote: addNoteAtPointer()
        case .addFrame: return addFrameAroundSelection()
        default: return false // `perform(_:)` routes every other command elsewhere.
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

    /// The palette's keys, and Escape.
    private func performPaletteCommand(_ command: GraphKeyCommand) -> Bool {
        switch command {
        case .cancel: return cancel()
        case .paletteUp: movePaletteHighlight(by: -1)
        case .paletteDown: movePaletteHighlight(by: 1)
        case .paletteConfirm: confirmPalette()
        default: return false // `perform(_:)` routes every other command elsewhere.
        }
        return true
    }

    /// Escape, in order (spec 2026-10-09 §3): closes the palette; else ends the drag under way
    /// (`cancelInteraction()`); else clears the selection. With none of these to do it returns false, and the key
    /// goes on. A pick's, a sketch's and the theme editor's Esc are button shortcuts, which MetalUI runs first.
    private func cancel() -> Bool {
        if palette != nil {
            closePalette()
            return true
        }
        if cancelInteraction() { return true }
        guard !canvasSelection.isEmpty else { return false }
        clearSelection()
        return true
    }
}
