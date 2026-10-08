import CreatorGeometry

extension EditorModel {
    /// Tab or Space: opens the add-node palette under the pointer (or the canvas corner).
    public func openPalette() {
        palette = SearchPaletteState(screenPosition: pointerLocation ?? Vector2(24, 24))
    }

    public func closePalette() { palette = nil }

    /// The palette's matches for its current query.
    public var paletteEntries: [PaletteEntry] {
        guard let palette else { return [] }
        return PaletteSearch.entries(in: registry, matching: palette.query)
    }

    public func setPaletteQuery(_ query: String) {
        palette?.query = query
        palette?.highlighted = 0
    }

    /// Moves the highlight by `step`, clamped to the matches.
    public func movePaletteHighlight(by step: Int) {
        guard let palette else { return }
        let count = paletteEntries.count
        guard count > 0 else { return }
        self.palette?.highlighted = min(max(palette.highlighted + step, 0), count - 1)
    }

    /// Return: adds the highlighted match (or `entry`) under the palette and closes it.
    public func confirmPalette(_ entry: PaletteEntry? = nil) {
        guard let palette else { return }
        let entries = paletteEntries
        guard let chosen = entry ?? (entries.indices.contains(palette.highlighted) ? entries[palette.highlighted] : nil) else { return }
        closePalette()
        addNode(chosen.typeID, atScreen: palette.screenPosition)
    }
}
