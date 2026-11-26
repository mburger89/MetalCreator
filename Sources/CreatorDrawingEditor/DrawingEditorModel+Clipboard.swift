import CreatorDrawing
import CreatorGeometry

extension DrawingEditorModel {
    /// Puts the selected views, with all their annotations, and the selected annotations of other views in the editor's clipboard
    /// (DR-5 R18). A derived view without the view it was made from is refused, and the clipboard stays as it was.
    @discardableResult
    public func copySelection() -> Bool {
        guard let current = sheet, !selection.isEmpty || !selectedAnnotations.isEmpty else { return false }
        let views = current.views.filter { selection.contains($0.id) }
        for view in views {
            if let derivation = view.derivation, !selection.contains(derivation.parent) {
                refuse(SheetCopy.derivedAloneRefusal)
                return false
            }
        }
        let annotations = current.annotations.filter { annotation in
            if let owner = annotation.view, selection.contains(owner) { return true }
            return selectedAnnotations.contains(annotation.id)
        }
        guard !views.isEmpty || !annotations.isEmpty else { return false }
        clipboard = DrawingClipboard(
            sheet: current.id, sheetScale: current.scale, views: views, annotations: annotations)
        refusal = nil
        return true
    }

    /// Copy, then one "Cut" step that deletes the selection.
    @discardableResult
    public func cutSelection() -> Bool {
        guard copySelection() else { return false }
        removeSelection(named: DrawingStepName.cut)
        return true
    }

    /// Pastes the clipboard on the open sheet (DR-5 R18): new ids, (10, -10) mm further for each paste, one "Paste" step; the pasted
    /// things are selected. What can't be pasted is said in `refusal`.
    @discardableResult
    public func paste() -> Bool {
        guard let board = clipboard, let id = currentSheet, let target = sheet else { return false }
        var views = board.views
        // A view that followed its sheet's scale keeps its size on a sheet of another scale; the first view on an empty sheet sets nothing.
        if !target.views.isEmpty, target.scale != board.sheetScale {
            for index in views.indices where views[index].scale == nil { views[index].scale = board.sheetScale }
        }
        let step = Double(board.pastes + 1)
        let made = SheetCopy.copy(
            views: views, annotations: board.annotations, onto: target, offset: Vector2(10 * step, -10 * step))
        guard !made.views.isEmpty || !made.annotations.isEmpty else {
            refuse(made.skipped.joined(separator: " "))
            return false
        }
        commitSheet(id, DrawingStepName.paste) { $0 = made.sheet }
        clipboard?.pastes += 1
        selection = Set(made.views)
        selectedAnnotations = Set(made.annotations)
        hoveredStroke = nil
        if !made.skipped.isEmpty { refuse(made.skipped.joined(separator: " ")) }
        return true
    }
}
