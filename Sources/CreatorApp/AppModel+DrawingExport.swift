import CreatorDrawing
import CreatorDrawingEditor
import CreatorGraph
import CreatorKernel
import Foundation

/// PDF and DXF export of the drawings (plan R25). Each export commits a pending entry, waits for evaluation, refuses what can't be
/// drawn, projects what it writes and writes in one go; the warnings (meshes left out, replaced characters) come back for the summary.
extension AppModel {
    /// What an export writes: its sheets (every one for a PDF, the open one for a DXF of the sheet, the view's for a DXF of a view)
    /// and the one view of a DXF at 1:1.
    struct DrawingExportPlan {
        var sheets: [DrawingSheet]
        var openSheet: DrawingSheet?
        var view: DrawingView?
    }

    /// Says what's wrong before anything is asked or projected: no sheet, no single selected view, an Output a written view shows
    /// that failed.
    func drawingExportPlan(_ kind: DrawingExportKind) throws(AppProblem) -> DrawingExportPlan {
        let editor = drawing.editor
        let drawings = editor.document
        guard !drawings.sheets.isEmpty else {
            throw AppProblem("Nothing to export", "Add a sheet with a view first.")
        }
        let open = editor.currentSheet.flatMap { drawings.sheet($0) } ?? drawings.sheets[0]
        var plan = DrawingExportPlan(sheets: drawings.sheets, openSheet: open, view: nil)
        switch kind {
        case .pdf: break
        case .dxfSheet: plan.sheets = [open]
        case .dxfView:
            let selected = open.views.filter { editor.selection.contains($0.id) }
            guard selected.count == 1, editor.selection.count == 1 else {
                throw AppProblem("Nothing to export", "Select one view to export it at 1:1.")
            }
            plan.view = selected[0]
            plan.sheets = [open]
        }
        let shown = plan.view.map { [$0] } ?? plan.sheets.flatMap(\.views)
        for view in shown {
            let source = DrawingSession.content(of: view.source, in: document)
            switch source.state {
            case .failed(let message): throw AppProblem("“\(source.name)” can't be drawn", message)
            case .removed: throw AppProblem("A view can't be drawn", DrawingProjector.removedSentence)
            case .ready(let solids, let curves, let meshCount) where solids.isEmpty && curves.isEmpty:
                let reason = meshCount > 0 ? DrawingProjector.onlyMeshesSentence : DrawingProjector.nothingYetSentence
                throw AppProblem("“\(source.name)” can't be drawn", reason)
            default: break
            }
        }
        return plan
    }

    /// A view whose projection failed now would print its last good one: refuse it by name, as a failed Output is.
    private func refuseProblemViews(in plan: DrawingExportPlan, _ snapshot: DrawingSnapshot) throws(AppProblem) {
        for view in plan.view.map({ [$0] }) ?? plan.sheets.flatMap(\.views) {
            if let problem = snapshot.contents[view.id]?.problem {
                let name = DrawingSession.content(of: view.source, in: document).name
                throw AppProblem("“\(name)” can't be drawn", problem)
            }
        }
    }

    /// The name offered: "<exportName>.pdf", "<exportName>.dxf" or "<exportName> <view title>.dxf".
    func defaultDrawingName(_ kind: DrawingExportKind, _ plan: DrawingExportPlan) -> String {
        guard kind == .dxfView, let view = plan.view, let sheet = plan.openSheet else {
            return "\(exportName).\(kind.fileExtension)"
        }
        var unscaled = view
        unscaled.scale = nil
        let title = ViewLabel.text(for: unscaled, sheet: sheet, standard: drawing.editor.document.settings.standard)
        return "\(exportName) \(title).dxf"
    }

    /// Export PDF…, DXF of Sheet… or DXF of View at 1:1…: says what's wrong before asking where, then the save panel, then the file.
    public func exportDrawing(_ kind: DrawingExportKind, using picker: any FilePicker) async {
        let picker = tracked(picker)
        commitPendingEntries()
        await document.waitForEvaluation()
        do {
            let plan = try drawingExportPlan(kind)
            guard let url = try await picker.chooseDestination([.exported(kind)],
                                                               defaultName: defaultDrawingName(kind, plan)) else { return }
            summarize(try await exportDrawingReturningWarnings(kind, to: url))
        } catch {
            report(error, title: "The drawing couldn't be exported")
        }
    }

    /// Writes the drawing to `url` once the document has evaluated; the warnings come back instead of raising the summary alert
    /// (an AI client's export is not the person's).
    public func exportDrawingReturningWarnings(_ kind: DrawingExportKind, to url: URL) async throws(AppProblem) -> [String] {
        commitPendingEntries()
        await document.waitForEvaluation()
        let plan = try drawingExportPlan(kind)
        let snapshot = await drawing.projectAll()
        let drawings = drawing.editor.document
        try refuseProblemViews(in: plan, snapshot)
        let style = DrawingStyle.of(drawings.settings.standard)
        let data: Data
        var replaced: [String]
        switch kind {
        case .pdf:
            let pages = drawings.sheets.map { sheet in
                SheetComposer.compose(sheet, in: drawings, contents: snapshot.contents,
                                      facts: snapshot.facts[sheet.id] ?? TitleBlockFacts(), notices: false)
            }
            let output = PDFWriter.write(pages, title: exportName)
            (data, replaced) = (output.data, output.replacedTexts)
        case .dxfSheet:
            guard let sheet = plan.openSheet else { throw AppProblem("Nothing to export", "Add a sheet with a view first.") }
            let picture = SheetComposer.compose(sheet, in: drawings, contents: snapshot.contents,
                                                facts: snapshot.facts[sheet.id] ?? TitleBlockFacts(), notices: false)
            let output = DXFWriter.sheet(picture, style: style)
            (data, replaced) = (output.data, output.replacedTexts)
        case .dxfView:
            guard let view = plan.view else { throw AppProblem("Select one view", "Select one view to export it at 1:1.") }
            guard let projection = snapshot.contents[view.id]?.projection else {
                let reason = snapshot.contents[view.id]?.problem ?? DrawingProjector.nothingYetSentence
                throw AppProblem("The view can't be drawn", reason)
            }
            let output = DXFWriter.view(projection, view: view, style: style)
            (data, replaced) = (output.data, output.replacedTexts)
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw AppProblem("The \(kind.title) file couldn't be written", Evaluator.message(for: error))
        }
        var warnings: [String] = []
        let shown = plan.view.map { [$0] } ?? plan.sheets.flatMap(\.views)
        for view in shown {
            for warning in snapshot.contents[view.id]?.warnings ?? [] where !warnings.contains(warning) { warnings.append(warning) }
        }
        var seen: Set<String> = []
        replaced = replaced.filter { seen.insert($0).inserted }
        if !replaced.isEmpty {
            let texts = replaced.map { "“\($0)”" }.joined(separator: ", ")
            warnings.append("The lettering can't draw some characters, so they show as “?”: \(texts).")
        }
        return warnings
    }
}
