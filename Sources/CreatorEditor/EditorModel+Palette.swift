import CreatorGeometry
import CreatorGraph

extension EditorModel {
    /// Tab or Space: opens the add-node palette under the pointer (or the canvas corner). It floats over the window
    /// (`SearchPaletteOverlay`), anchored at the pointer's window point (`pointerWindowLocation`, which the canvas's
    /// `.global` hover reports, so it needs neither a placed panel nor a drawn viewport); the node it adds still lands
    /// at the canvas point where it opened.
    public func openPalette() {
        let screen = pointerLocation ?? Vector2(24, 24)
        let window = pointerLocation == nil ? nil : pointerWindowLocation
        palette = SearchPaletteState(screenPosition: screen, windowPoint: window ?? windowPoint(fromCanvas: screen))
    }

    public func closePalette() { palette = nil }

    /// The palette's matches for its current query.
    public var paletteEntries: [PaletteEntry] {
        guard let palette else { return [] }
        return PaletteSearch.entries(in: registry, matching: palette.query)
    }

    /// The matches in view: `PaletteLayout.visibleRows` from `firstVisible`.
    public var paletteVisibleEntries: [PaletteEntry] {
        guard let palette else { return [] }
        return Array(paletteEntries.dropFirst(palette.firstVisible).prefix(PaletteLayout.visibleRows))
    }

    /// How many matches are out of view.
    public var paletteHiddenCount: Int { paletteEntries.count - paletteVisibleEntries.count }

    public func setPaletteQuery(_ query: String) {
        palette?.query = query
        palette?.highlighted = 0
        palette?.firstVisible = 0
    }

    /// Moves the highlight by `step`, clamped to the matches, scrolling the rows to keep it in view.
    public func movePaletteHighlight(by step: Int) {
        guard let palette else { return }
        let count = paletteEntries.count
        guard count > 0 else { return }
        let highlighted = min(max(palette.highlighted + step, 0), count - 1)
        var first = palette.firstVisible
        if highlighted < first { first = highlighted }
        if highlighted >= first + PaletteLayout.visibleRows { first = highlighted - PaletteLayout.visibleRows + 1 }
        self.palette?.highlighted = highlighted
        self.palette?.firstVisible = first
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
