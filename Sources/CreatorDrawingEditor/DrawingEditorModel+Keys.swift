import CreatorDrawing
import CreatorGeometry

extension DrawingEditorModel {
    /// Answers a key; `true` when it did something.
    @discardableResult
    public func keyPressed(_ key: DrawingKey) -> Bool {
        switch key {
        case .fit:
            fit()
            return true
        case .delete:
            guard !selection.isEmpty else { return false }
            deleteSelection()
            return true
        case .nudge(let delta):
            return nudge(by: delta)
        case .escape:
            if gesture != nil {
                gesture = nil
                return true
            }
            if tool != .select {
                tool = .select
                refusal = nil
                return true
            }
            if !selection.isEmpty {
                selection = []
                return true
            }
            return false
        }
    }

    private func nudge(by delta: Vector2) -> Bool {
        guard let id = currentSheet, !selection.isEmpty, delta.length > 0 else { return false }
        let chosen = selection
        commitSheet(id, DrawingStepName.moveView, key: "drawing-nudge") { sheet in
            sheet = Self.moved(chosen, by: delta, in: sheet)
        }
        return true
    }

    /// Moves each chosen view that has no chosen ancestor; its aligned descendants go with it.
    static func moved(_ chosen: Set<ViewID>, by delta: Vector2, in sheet: DrawingSheet) -> DrawingSheet {
        var result = sheet
        for id in roots(of: chosen, in: sheet) { result = ViewPlacement.moving(id, by: delta, in: result) }
        return result
    }

    static func roots(of chosen: Set<ViewID>, in sheet: DrawingSheet) -> [ViewID] {
        sheet.views.map(\.id).filter { id in
            guard chosen.contains(id) else { return false }
            var seen: Set<ViewID> = [id]
            var next = sheet.view(id)?.alignment?.parent
            while let parent = next, seen.insert(parent).inserted {
                if chosen.contains(parent) { return false }
                next = sheet.view(parent)?.alignment?.parent
            }
            return true
        }
    }
}
