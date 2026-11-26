import CreatorDrawing
import CreatorGeometry
import Foundation

extension DrawingEditorModel {
    /// Answers a key; `true` when it did something.
    @discardableResult
    public func keyPressed(_ key: DrawingKey) -> Bool {
        switch key {
        case .fit:
            fit()
            return true
        case .delete:
            guard !selection.isEmpty || !selectedAnnotations.isEmpty else { return false }
            deleteSelection()
            return true
        case .nudge(let delta, let isRepeat):
            return nudge(by: delta, isRepeat: isRepeat)
        case .tool(let tool):
            press(tool)
            return true
        case .finish:
            return finishSectionDraft()
        case .escape:
            return escapePressed()
        }
    }

    /// Esc: cancels a drag, then drops a draft, the annotation input, the tool and finally the selection.
    private func escapePressed() -> Bool {
        if gesture != nil {
            pointerCancelled()
            return true
        }
        if dropToolDrafts() { return true }
        if holdsAnnotationInput {
            cancelAnnotationInput()
            return true
        }
        if tool != .select {
            tool = .select
            refusal = nil
            return true
        }
        if !selection.isEmpty || !selectedAnnotations.isEmpty {
            selection = []
            selectedAnnotations = []
            return true
        }
        return false
    }

    private func nudge(by delta: Vector2, isRepeat: Bool) -> Bool {
        guard let id = currentSheet, let current = sheet, !selection.isEmpty || !selectedAnnotations.isEmpty, delta.length > 0
        else { return false }
        let roots = Self.roots(of: selection, in: current)
        let seeds = seeds(for: selectedAnnotations, pressing: nil)
        let name = moveName(roots: roots, seeds: seeds, in: current)
        if !isRepeat || nudgeKey == nil { nudgeKey = "drawing-nudge-\(UUID().uuidString)" }
        commitSheet(id, name, key: nudgeKey) { sheet in
            sheet = Self.movedSheet(sheet, roots: roots, seeds: seeds, by: delta)
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
            // A chosen aligned or derived ancestor carries this view along (a visited set ends any cycle).
            var seen: Set<ViewID> = [id]
            var frontier = [id]
            while let current = frontier.popLast() {
                guard let view = sheet.view(current) else { continue }
                for parent in [view.alignment?.parent, view.derivation?.parent].compactMap({ $0 }) where seen.insert(parent).inserted {
                    if chosen.contains(parent) { return false }
                    frontier.append(parent)
                }
            }
            return true
        }
    }
}
