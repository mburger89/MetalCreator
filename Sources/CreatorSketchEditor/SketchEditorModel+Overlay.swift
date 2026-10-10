import CreatorSketch
import CreatorViewport

extension SketchEditorModel {
    /// What the viewport draws while this sketch is edited (`ViewportModel.showOverlay(_:)`): the curves, the region fills
    /// under them, the rubber band and the dimensions' labels. The Dimension tool's first pick is drawn selected.
    public var overlay: ViewportOverlay {
        let picked = dimensionPick.map { selection.union([$0]) } ?? selection
        return SketchOverlayBuilder.overlay(sketch: sketch, solution: solution, plane: plane, selection: picked, hovered: hovered,
                                            preview: preview, fills: regionFills, labels: dimensionLabels)
    }

    /// One fill per closed region of the sketch as it is now (spec §8), found again only when the sketch or its plane
    /// changed (a drag changes it every step; a hover never does).
    var regionFills: [OverlayFill] {
        if let cache = fillCache, cache.sketch == sketch, cache.plane == plane { return cache.fills }
        let fills = SketchRegionFills.fills(of: sketch, on: plane)
        fillCache = (sketch, plane, fills)
        return fills
    }

    /// A label for each dimension whose geometry is there (`SketchDimensionLabels`); a dimension in a conflict is red.
    var dimensionLabels: [OverlayLabel] {
        let conflicting = Set(conflictRefs.compactMap { ref -> DimensionID? in
            if case .dimension(let id) = ref { id } else { nil }
        })
        return SketchDimensionLabels.labels(sketch: sketch, solution: solution, plane: plane, conflicting: conflicting)
    }
}
