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

    /// Says what's wrong before anything is asked or projected: no sheet, no single selected view, an Output (or a part) a written view
    /// shows that failed. `sheet` and `view` name what to write (an AI client's export); without them the open sheet and the selection.
    func drawingExportPlan(
        _ kind: DrawingExportKind, sheet requested: SheetID? = nil, view requestedView: ViewID? = nil
    ) throws(AppProblem) -> DrawingExportPlan {
        let editor = drawing.editor
        let drawings = editor.document
        guard !drawings.sheets.isEmpty else {
            throw AppProblem("Nothing to export", "Add a sheet with a view first.")
        }
        let open: DrawingSheet
        if let requested {
            guard let found = drawings.sheet(requested) else { throw AppProblem("Nothing to export", "There's no such sheet.") }
            open = found
        } else {
            open = editor.currentSheet.flatMap { drawings.sheet($0) } ?? drawings.sheets[0]
        }
        var plan = DrawingExportPlan(sheets: drawings.sheets, openSheet: open, view: nil)
        switch kind {
        case .pdf: break
        case .pdfSheet, .dxfSheet, .svgSheet: plan.sheets = [open]
        case .dxfView, .dxfViewWithAnnotations:
            plan.view = try exportedView(in: open, requested: requestedView)
            plan.sheets = [open]
        }
        for view in plan.view.map({ [$0] }) ?? plan.sheets.flatMap(\.views) {
            if let problem = refusal(for: view) { throw problem }
        }
        return plan
    }

    /// The one view a DXF at 1:1 writes: the named one, else the one selected view.
    private func exportedView(in sheet: DrawingSheet, requested: ViewID?) throws(AppProblem) -> DrawingView {
        if let requested {
            guard let found = sheet.view(requested) else { throw AppProblem("Nothing to export", "There's no such view.") }
            return found
        }
        let editor = drawing.editor
        let selected = sheet.views.filter { editor.selection.contains($0.id) }
        guard selected.count == 1, editor.selection.count == 1 else {
            throw AppProblem("Nothing to export", "Select one view to export it at 1:1.")
        }
        return selected[0]
    }

    /// Why `view` can't be written, or `nil`: a failed Output (a failed part is named), every part removed, or nothing to draw. A part
    /// of an assembly that was removed, is empty or holds a mesh is only left out with a warning (R2).
    private func refusal(for view: DrawingView) -> AppProblem? {
        let sources = drawing.sources(of: view)
        for source in sources {
            if case .failed(let message) = source.state { return AppProblem("“\(source.name)” can't be drawn", message) }
        }
        var removed = 0, meshes = 0
        var drawable = false, evaluating = false
        for source in sources {
            switch source.state {
            case .removed: removed += 1
            case .ready(let solids, let curves, let meshCount):
                meshes += meshCount
                drawable = drawable || !solids.isEmpty || !curves.isEmpty
            case .evaluating: evaluating = true
            case .failed: break
            }
        }
        if removed == sources.count { return AppProblem("A view can't be drawn", DrawingProjector.removedSentence) }
        if !drawable, !evaluating {
            let reason = meshes > 0 ? DrawingProjector.onlyMeshesSentence : DrawingProjector.nothingYetSentence
            return AppProblem("“\(sources.first?.name ?? "")” can't be drawn", reason)
        }
        return nil
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
        guard kind == .dxfView || kind == .dxfViewWithAnnotations, let view = plan.view, let sheet = plan.openSheet else {
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

    /// A written file's bytes, the typed texts its lettering replaced, the sentences about what its sheets carry (lost annotations,
    /// then checks, then an unreadable logo, sheet by sheet) and whether a logo had to be left out (a DXF holds no picture).
    struct DrawingFile {
        var data: Data
        var replaced: [String]
        var lost: [String]
        var leftOutLogo = false
    }

    /// DXF R13: said once per file.
    static let dxfLogoSentence = "The DXF leaves out the title block's logo; DXF files can't hold a picture."

    /// Writes the drawing to `url` once the document has evaluated; the warnings come back instead of raising the summary alert
    /// (an AI client's export is not the person's).
    public func exportDrawingReturningWarnings(_ kind: DrawingExportKind, to url: URL) async throws(AppProblem) -> [String] {
        try await exportDrawingReturningWarnings(kind, sheet: nil, view: nil, to: url)
    }

    /// The same for the named sheet and view (an AI client's); without them the open sheet and the selection.
    public func exportDrawingReturningWarnings(
        _ kind: DrawingExportKind, sheet: SheetID?, view: ViewID?, to url: URL
    ) async throws(AppProblem) -> [String] {
        commitPendingEntries()
        await document.waitForEvaluation()
        let plan = try drawingExportPlan(kind, sheet: sheet, view: view)
        let snapshot = await drawing.projectAll(of: plan.sheets.map(\.id))
        try refuseProblemViews(in: plan, snapshot)
        let file = try drawingFile(kind, plan, snapshot)
        do {
            try file.data.write(to: url, options: .atomic)
        } catch {
            throw AppProblem("The \(kind.title) file couldn't be written", Evaluator.message(for: error))
        }
        var warnings: [String] = []
        let shown = plan.view.map { [$0] } ?? plan.sheets.flatMap(\.views)
        for view in shown {
            for warning in snapshot.contents[view.id]?.warnings ?? [] where !warnings.contains(warning) { warnings.append(warning) }
        }
        warnings += file.lost
        if file.leftOutLogo { warnings.append(Self.dxfLogoSentence) }
        var seen: Set<String> = []
        let replaced = file.replaced.filter { seen.insert($0).inserted }
        if !replaced.isEmpty {
            let texts = replaced.map { "“\($0)”" }.joined(separator: ", ")
            warnings.append("The lettering can't draw some characters, so they show as “?”: \(texts).")
        }
        return warnings
    }

    /// The bytes of `kind` for what `plan` writes, composed with the document's units and the editor's remembered last good values
    /// (plan R15), with the sentences about the annotations that lost what they were attached to (plan R15, R22).
    private func drawingFile(_ kind: DrawingExportKind, _ plan: DrawingExportPlan, _ snapshot: DrawingSnapshot)
        throws(AppProblem) -> DrawingFile {
        let drawings = drawing.editor.document
        let style = DrawingStyle.of(drawings.settings.standard)
        let (units, remembered) = (document.units, drawing.editor.remembered)
        func picture(of sheet: DrawingSheet) -> SheetPicture {
            SheetComposer.compose(
                sheet, in: drawings, contents: snapshot.contents, facts: snapshot.facts[sheet.id] ?? TitleBlockFacts(), notices: false,
                units: units, remembered: remembered)
        }
        /// What a sheet says about itself in a file, in R15's order: its lost annotations, its checks, its unreadable logo.
        func warnings(of sheet: DrawingSheet, in page: SheetPicture, view: ViewID?) -> [String] {
            var sentences = Self.lostWarnings(on: sheet, in: page, view: view) + Self.checkWarnings(on: sheet, in: page, view: view)
            if view == nil, case .unreadable(let reason)? = snapshot.facts[sheet.id]?.logo {
                sentences.append(SheetComposer.logoUnreadableSentence(reason))
            }
            return sentences
        }
        switch kind {
        case .pdf, .pdfSheet:
            let sheets = kind == .pdf ? drawings.sheets : (plan.openSheet.map { [$0] } ?? [])
            guard !sheets.isEmpty else { throw AppProblem("Nothing to export", "Add a sheet with a view first.") }
            let pictures = sheets.map(picture(of:))
            let lost = zip(sheets, pictures).flatMap { warnings(of: $0, in: $1, view: nil) }
            let output = PDFWriter.write(pictures, title: exportName)
            return DrawingFile(data: output.data, replaced: output.replacedTexts, lost: lost)
        case .svgSheet:
            guard let sheet = plan.openSheet else { throw AppProblem("Nothing to export", "Add a sheet with a view first.") }
            let page = picture(of: sheet)
            let output = SVGWriter.write(page, title: exportName)
            return DrawingFile(data: output.data, replaced: output.replacedTexts, lost: warnings(of: sheet, in: page, view: nil))
        case .dxfSheet:
            guard let sheet = plan.openSheet else { throw AppProblem("Nothing to export", "Add a sheet with a view first.") }
            let page = picture(of: sheet)
            let output = DXFWriter.sheet(page, style: style)
            return DrawingFile(
                data: output.data, replaced: output.replacedTexts, lost: warnings(of: sheet, in: page, view: nil),
                leftOutLogo: output.leftOutImages)
        case .dxfView, .dxfViewWithAnnotations:
            return try viewFile(kind, plan, snapshot, picture: picture(of:), warnings: warnings(of:in:view:))
        }
    }

    /// A DXF of one view at 1:1, with its annotations mapped back to model millimetres for `.dxfViewWithAnnotations`.
    private func viewFile(
        _ kind: DrawingExportKind, _ plan: DrawingExportPlan, _ snapshot: DrawingSnapshot,
        picture: (DrawingSheet) -> SheetPicture, warnings: (DrawingSheet, SheetPicture, ViewID?) -> [String]
    ) throws(AppProblem) -> DrawingFile {
        let style = DrawingStyle.of(drawing.editor.document.settings.standard)
        guard let view = plan.view else { throw AppProblem("Select one view", "Select one view to export it at 1:1.") }
        guard let content = snapshot.contents[view.id], let projection = content.projection else {
            let reason = snapshot.contents[view.id]?.problem ?? DrawingProjector.nothingYetSentence
            throw AppProblem("The view can't be drawn", reason)
        }
        guard kind == .dxfViewWithAnnotations, let sheet = plan.openSheet else {
            let output = DXFWriter.view(projection, view: view, style: style)
            return DrawingFile(data: output.data, replaced: output.replacedTexts, lost: [])
        }
        let page = picture(sheet)
        let scale = (view.scale ?? sheet.scale).value
        let center = ViewPlacement.centers(in: sheet)[view.id] ?? view.center
        let mapping = ViewMapping.of(content: content, center: center, scale: scale) ?? ViewMapping(scale: scale, offset: center)
        let output = DXFWriter.view(projection, view: view, style: style, annotations: (page, mapping))
        return DrawingFile(data: output.data, replaced: output.replacedTexts, lost: warnings(sheet, page, view.id))
    }

    /// At most this many lost annotations are listed one by one per sheet (plan R15).
    static let listedLostPerSheet = 10

    /// The lost annotations of `sheet`'s picture, one sentence each in sheet order (the first `listedLostPerSheet`), then one more for
    /// the rest; `view` limits them to the annotations of that view.
    static func lostWarnings(on sheet: DrawingSheet, in picture: SheetPicture, view: ViewID?) -> [String] {
        let lost = picture.lostAnnotations.filter { id in view == nil || sheet.annotation(id)?.view == view }
        var sentences: [String] = []
        for id in lost.prefix(listedLostPerSheet) {
            guard let report = picture.annotationReports[id], case .lost(let reason) = report.status else { continue }
            let text = report.label.isEmpty ? "?" : report.label
            sentences.append("On “\(sheet.name)”, “\(text)” lost what it was attached to: \(reason.sentence)")
        }
        let more = lost.count - listedLostPerSheet
        if more > 0 {
            let count = more.formatted(.number.locale(.messages))
            sentences.append(more == 1
                ? "On “\(sheet.name)”, \(count) more annotation lost what it was attached to."
                : "On “\(sheet.name)”, \(count) more annotations lost what they were attached to.")
        }
        return sentences
    }

    /// At most this many symbols with warnings are listed one by one per sheet (DR-4 R13).
    static let listedChecksPerSheet = 10

    /// The rules the symbols of `sheet` break, one sentence per warning in sheet order (the first `listedChecksPerSheet` symbols),
    /// then one more for the rest; `view` limits them to the symbols of that view.
    static func checkWarnings(on sheet: DrawingSheet, in picture: SheetPicture, view: ViewID?) -> [String] {
        let checked = picture.checkedAnnotations.filter { id in view == nil || sheet.annotation(id)?.view == view }
        var sentences: [String] = []
        for id in checked.prefix(listedChecksPerSheet) {
            guard let report = picture.annotationReports[id] else { continue }
            let text = report.label.isEmpty ? "?" : report.label
            for warning in report.warnings { sentences.append("On “\(sheet.name)”, “\(text)”: \(warning)") }
        }
        let more = checked.count - listedChecksPerSheet
        if more > 0 {
            let count = more.formatted(.number.locale(.messages))
            sentences.append(more == 1
                ? "On “\(sheet.name)”, \(count) more symbol has a warning."
                : "On “\(sheet.name)”, \(count) more symbols have warnings.")
        }
        return sentences
    }
}
