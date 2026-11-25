import CreatorDrawing

extension DocumentModel {
    /// All of the editor state as the file's `ViewState`. Reading it reads every piece; to observe one, read the piece.
    /// Writing it sets only the pieces that differ, so a write that changes one field invalidates only that field's readers.
    public var viewState: ViewState {
        get {
            ViewState(dock: dock, canvasOffset: canvasOffset, canvasZoom: canvasZoom, camera: camera, homeCamera: homeCamera,
                      showsLibrary: showsLibrary, librarySort: librarySort, section: section, measurements: measurements, zebra: zebra,
                      drawing: drawingView)
        }
        set {
            if dock != newValue.dock { dock = newValue.dock }
            if canvasOffset != newValue.canvasOffset { canvasOffset = newValue.canvasOffset }
            if canvasZoom != newValue.canvasZoom { canvasZoom = newValue.canvasZoom }
            if camera != newValue.camera { camera = newValue.camera }
            if homeCamera != newValue.homeCamera { homeCamera = newValue.homeCamera }
            if showsLibrary != newValue.showsLibrary { showsLibrary = newValue.showsLibrary }
            if librarySort != newValue.librarySort { librarySort = newValue.librarySort }
            if section != newValue.section { section = newValue.section }
            if measurements != newValue.measurements { measurements = newValue.measurements }
            if zebra != newValue.zebra { zebra = newValue.zebra }
            if drawingView != newValue.drawing { drawingView = newValue.drawing }
        }
    }
}
