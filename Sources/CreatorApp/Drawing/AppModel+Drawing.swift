import CreatorDrawing
import CreatorDrawingEditor
import CreatorGraph
import CreatorKernel

/// Drawing mode in the app (drawings plan R4, R19 to R21, R28). The mode and the sheet are the document's view state
/// (`DocumentModel.drawingView`): switching is never an edit and never an undo step.
extension AppModel {
    /// What the model area shows.
    public var mode: WorkspaceMode { document.drawingView?.isOn == true ? .drawing : .model }

    /// The projections' cache, one per open document (a new one on New and Open).
    public var projectionCache: ProjectionCache { drawing.cache }

    /// Commits what is typed and not yet entered, in the graph's inspector and in the drawing's: the one call every moment that would
    /// lose it (Save, Undo, an export, a mode switch, the close request) makes.
    func commitPendingEntries() {
        editor.commitPendingEntry()
        drawing.editor.commitPendingEntry()
    }

    /// The top bar's "Model | Drawing", View ▸ Drawing (⌘⇧D) and View ▸ Model. Entering Drawing finishes the sketch, cancels a pick and
    /// ends Measure, the model dimension tool and the control-point mode (R21); the section's, zebra's and kept measurements' state is
    /// left as it was, so Model shows them again (R28).
    public func setMode(_ new: WorkspaceMode) {
        guard new != mode else { return }
        commitPendingEntries()
        editor.closePalette()
        if new == .drawing {
            if sketch != nil { finishSketch() }
            cancelPick()
            endMeasure()
            endModelDimension()
            endControlPoints()
            document.drawingView = DrawingViewState(isOn: true, sheet: drawing.editor.currentSheet)
            drawing.activate()
        } else {
            let sheet = drawing.editor.currentSheet
            document.drawingView = sheet.map { DrawingViewState(isOn: false, sheet: $0) }
            drawing.deactivate()
        }
        sceneInputsChanged()
    }

    /// An inspector action that needs the viewport switches back to Model first, then runs (R21).
    func leaveDrawingForViewport() {
        if mode == .drawing { setMode(.model) }
    }

    /// One drawing edit from the editor, stored as one named undo step; refused (and the editor put back) while an alert is up or a
    /// result is held, as other edits are.
    func storeDrawing(_ commit: DrawingCommit) {
        guard alert == nil, !document.isHoldingResults else {
            drawing.resync()
            return
        }
        do {
            try document.perform(.setDrawings(commit.document), coalescingKey: commit.coalescingKey,
                                 name: UndoName.drawing(commit.name))
        } catch {
            alert = .problem(AppProblem("The drawing couldn't be changed", error.message))
        }
        refreshDrawing()
    }

    /// The editor sheet changed: remember it in the view state.
    func drawingSheetChanged(_ sheet: SheetID?) {
        let isOn = document.drawingView?.isOn == true
        let state = sheet.map { DrawingViewState(isOn: isOn, sheet: $0) } ?? (isOn ? DrawingViewState(isOn: true) : nil)
        if document.drawingView != state { document.drawingView = state }
    }

    /// Follows the document's drawings, sources and results (every scene refresh and every drawing edit).
    func refreshDrawing() {
        drawing.update()
    }
}
