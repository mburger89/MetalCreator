import CreatorViewport

extension SketchEditorModel {
    /// What the viewport draws while this sketch is edited (`ViewportModel.showOverlay(_:)`). The Dimension tool's
    /// first pick is drawn selected.
    public var overlay: ViewportOverlay {
        let picked = dimensionPick.map { selection.union([$0]) } ?? selection
        return SketchOverlayBuilder.overlay(sketch: sketch, solution: solution, plane: plane, selection: picked, hovered: hovered,
                                            preview: preview)
    }
}
