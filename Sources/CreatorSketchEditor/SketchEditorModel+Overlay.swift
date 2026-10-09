import CreatorViewport

extension SketchEditorModel {
    /// What the viewport draws while this sketch is edited (`ViewportModel.showOverlay(_:)`).
    public var overlay: ViewportOverlay {
        SketchOverlayBuilder.overlay(sketch: sketch, solution: solution, plane: plane, selection: selection, hovered: hovered,
                                     preview: preview)
    }
}
