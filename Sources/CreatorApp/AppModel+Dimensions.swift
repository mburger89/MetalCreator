import CreatorGraph
import CreatorKernel
import CreatorViewport

/// The dimensions drawn over the viewport: the open sketch's (DIM-1) and the features' (DIM-3, spec §3.3).
extension AppModel {
    /// What the viewport should show now (a query: it writes nothing; `refreshDimensions()` stores the table beside it):
    /// - a pick session: none;
    /// - a sketch open: the sketch's own, then the level's pinned dimensions ghosted (the open sketch node's own pins left out,
    ///   they are the sketch's dimensions already), no contextual ones;
    /// - otherwise: each selected node's (with its private chain), then the level's pins. Inside a group the level is the
    ///   definition's graph with its results.
    public func shownDimensions() -> [OverlayDimension] {
        dimensionsToShow().overlays
    }

    /// What to draw and the table of the feature dimensions among it, which is empty whenever none are drawn.
    private func dimensionsToShow() -> (overlays: [OverlayDimension], table: [OverlayDimensionID: FeatureDimension]) {
        var sketchDimensions: [OverlayDimension] = []
        var excluded: NodeID?
        if let session = sketch {
            guard session.isFollowing else { return ([], [:]) }
            sketchDimensions = session.editor.dimensions
            excluded = session.node
        } else if pick != nil {
            return ([], [:])
        }
        let isSketching = sketch != nil
        let graph = editor.graph
        let pins = graph.dimensionPins.filter { $0.node != excluded }
        let built = FeatureDimensionBuilder.dimensions(contextual: isSketching ? [] : editor.selection, pinned: pins,
                                                       held: isSketching ? nil : heldModelDimension, graph: graph,
                                                       content: document.content, results: editor.levelResults,
                                                       registry: registry, units: units, style: viewport.dimensionStyle)
        var features = built
        if isSketching {
            for index in features.indices { features[index].overlay.isGhosted = true }
        }
        let table = Dictionary(features.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return (sketchDimensions + features.map(\.overlay) + measureDimensions(), table)
    }

    /// Hands the viewport the dimensions it should show (`shownDimensions()`), when they changed, and keeps `featureDimensions`
    /// equal to the feature ones drawn. A value box whose dimension
    /// is gone closes.
    public func refreshDimensions() {
        let (shown, table) = dimensionsToShow()
        if featureDimensions != table { featureDimensions = table }
        if viewport.dimensions != shown { viewport.showDimensions(shown) }
        openPendingValueBox(among: shown)
    }

    /// Opens the value box of the dimension the model dimension tool just added, once the viewport shows it. A box that can't
    /// open (the dimension is not editable after all) forgets the held dimension, so it is not left on screen.
    private func openPendingValueBox(among shown: [OverlayDimension]) {
        guard let id = pendingValueBox, shown.contains(where: { $0.id == id }) else { return }
        pendingValueBox = nil
        guard !viewport.openValueBox(for: id) else { return }
        heldModelDimension = nil
        refreshDimensions()
    }
}
