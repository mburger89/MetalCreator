import CreatorDrawing
import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Details and pruning (DR-3 R14): a detail is its parent's content cut to a circle, made on the main actor with no kernel call, and
/// what the session holds for a view that is on no sheet is let go.
extension DrawingSession {
    /// Drops what the session holds for views on no sheet (R14): their requests, flights, generations and contents, so their
    /// solids are let go.
    func pruneGoneViews() {
        let live = Set(editor.document.sheets.flatMap { $0.views.map(\.id) })
        for id in Array(wanted.keys) where !live.contains(id) { wanted[id] = nil }
        for id in Array(applied.keys) where !live.contains(id) { applied[id] = nil }
        for id in Array(flights.keys) where !live.contains(id) {
            flights[id]?.task.cancel()
            flights[id] = nil
        }
        for id in Array(generations.keys) where !live.contains(id) { generations[id] = nil }
        for id in Array(detailInputs.keys) where !live.contains(id) { detailInputs[id] = nil }
        for id in Array(editor.contents.keys) where !live.contains(id) { editor.contents[id] = nil }
    }

    /// Gives a view its content and counts it, so the details of it know to follow (R14).
    func setContent(_ content: ViewContent, for id: ViewID) {
        editor.contents[id] = content
        generations[id, default: 0] += 1
    }

    /// Every detail of `sheet` made from its parent's content as it is now, parents first (R14); no kernel call. A detail whose
    /// parent has no content yet waits, faded; one whose parent is gone says so.
    func syncDetails(in sheet: DrawingSheet) {
        for view in sheet.viewsParentsFirst {
            guard view.kind == .detail, case .detail(let circle)? = view.derivation else { continue }
            let input = DetailInput(parentGeneration: generations[circle.parent] ?? 0, circle: circle)
            if detailInputs[view.id] == input, editor.contents[view.id] != nil { continue }
            let parentContent = editor.contents[circle.parent]
            let content: ViewContent
            if parentContent == nil, sheet.view(circle.parent) != nil {
                content = ViewContent(isPending: true)
            } else {
                content = DetailClip.content(of: parentContent, circle: circle)
            }
            if content.isPending { editor.feedingViews?.remove(view.id) } else if editor.feedingViews?.contains(circle.parent) == true {
                editor.feedingViews?.insert(view.id)
            }
            setContent(content, for: view.id)
            detailInputs[view.id] = input
        }
    }
}
