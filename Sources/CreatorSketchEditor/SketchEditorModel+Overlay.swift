import CreatorSketch
import CreatorViewport

extension SketchEditorModel {
    /// What the viewport draws while this sketch is edited (`ViewportModel.showOverlay(_:)`): the curves, the region fills
    /// under them, the rubber band. The Dimension tool's first pick is drawn selected.
    public var overlay: ViewportOverlay {
        let picked = dimensionPick.map { selection.union([$0]) } ?? selection
        return SketchOverlayBuilder.overlay(sketch: sketch, solution: solution, plane: plane, selection: picked, hovered: hovered,
                                            preview: preview, fills: regionFills)
    }

    /// One fill per closed region of the sketch as it is now (spec §8), found again only when the sketch or its plane
    /// changed (a drag changes it every step; a hover never does).
    var regionFills: [OverlayFill] {
        if let cache = fillCache, cache.sketch == sketch, cache.plane == plane { return cache.fills }
        let fills = SketchRegionFills.fills(of: sketch, on: plane)
        fillCache = (sketch, plane, fills)
        return fills
    }

    /// The sketch's dimensions as the viewport draws them (`ViewportModel.showDimensions(_:)`): one for each whose geometry
    /// is there (`SketchDimensionDrawing`), in `units`; a dimension in a conflict is red, a reference or wired one tinted
    /// as a reference.
    public var dimensions: [OverlayDimension] {
        let conflicting = Set(conflictRefs.compactMap { ref -> DimensionID? in
            if case .dimension(let id) = ref { id } else { nil }
        })
        return SketchDimensionDrawing.dimensions(sketch: sketch, solution: solution, plane: plane, conflicting: conflicting,
                                                 wired: wiredDimensions, units: units, style: .ansi)
    }
}
