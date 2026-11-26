import CreatorGeometry

/// Builds a sheet's whole picture: frame, title block and each view (plan R7, R11, R18).
public enum SheetComposer {
    static let defaultEmptySize = Vector2(40, 30)
    static let problemMargin = 4.0

    /// A view with where it sits and what it shows.
    private struct Placed {
        let view: DrawingView
        let center: Vector2
        let content: ViewContent
    }

    public static func compose(
        _ sheet: DrawingSheet, in document: DrawingDocument, contents: [ViewID: ViewContent], facts: TitleBlockFacts,
        notices: Bool = true, units: DocumentUnits = .millimetres, remembered: [AnnotationID: LastGood] = [:]
    ) -> SheetPicture {
        let settings = document.settings
        let standard = settings.standard
        let style = DrawingStyle.of(standard)
        var picture = SheetFrame.picture(for: sheet, standard: standard)
        picture.standard = standard
        let index = document.sheets.firstIndex { $0.id == sheet.id } ?? 0
        picture.append(
            TitleBlockLayout.picture(
                sheet: sheet, settings: settings, facts: facts, sheetIndex: index, sheetCount: document.sheets.count))
        let items = PartItems.numbered(document, names: PartItems.names(of: facts.parts))
        let base = notesBase(for: sheet, standard: standard, rows: items.count)
        let notes = SheetNotesLayout.picture(
            for: sheet, settings: settings, format: NumberFormat(units: units, settings: settings), base: base)
        picture.append(notes)
        if notices { appendLogoNotice(to: &picture, sheet: sheet, facts: facts, style: style, above: (notes, base)) }

        let centers = ViewPlacement.centers(in: sheet)
        let annotations = AnnotationPass(
            sheet: sheet, standard: standard, style: style, format: NumberFormat(units: units, settings: settings),
            remembered: remembered, rules: GDTRules.Context.make(document: document, sheet: sheet),
            items: items, partFacts: facts.parts)
        for view in sheet.views {
            let center = centers[view.id] ?? view.center
            let scale = (view.scale ?? sheet.scale).value
            let content = contents[view.id] ?? ViewContent()
            var frame: Rect2D
            if content.projection != nil {
                picture.strokes += ViewLinework.strokes(
                    for: content, view: view, center: center, scale: scale, style: style)
                picture.strokes += hatch(
                    for: view, content: content, center: center, scale: scale, sheet: sheet, style: style)
                frame = ViewLinework.frame(for: content, center: center, scale: scale)
                    ?? Rect2D(min: center, max: center)
            } else {
                frame = appendEmptyView(
                    to: &picture, placed: Placed(view: view, center: center, content: content), sheet: sheet, style: style,
                    notices: notices)
            }
            picture.viewFrames[view.id] = frame
            annotations.compose(
                view: view, center: center, scale: scale, content: content, frame: frame, into: &picture)
            appendLabel(to: &picture, view: view, center: center, frame: frame, sheet: sheet, style: style)
            if notices {
                appendNotices(
                    to: &picture, placed: Placed(view: view, center: center, content: content), frame: frame, sheet: sheet,
                    style: style, contents: contents)
            }
        }
        appendMarks(to: &picture, sheet: sheet, standard: standard, centers: centers, contents: contents)
        annotations.finish(&picture)
        return picture
    }

    /// The sentence for a title block logo that couldn't be read (DR-5 R11): a notice on screen and a warning in a file.
    public static func logoUnreadableSentence(_ reason: String) -> String {
        "The title block's logo couldn't be read: \(reason)"
    }

    /// The logo's sentence stands with the sheet notes above the title block, over whatever they hold, never at the frame's corner
    /// (drawings minors R19).
    private static func appendLogoNotice(
        to picture: inout SheetPicture, sheet: DrawingSheet, facts: TitleBlockFacts, style: DrawingStyle,
        above notes: (picture: SheetPicture, base: Double?)
    ) {
        guard case .unreadable(let reason)? = facts.logo else { return }
        let height = style.notesHeight(for: sheet.size)
        let sentence = logoUnreadableSentence(reason)
        let origin = TitleBlockLayout.origin(for: sheet, standard: style.standard)
        var top = notes.base ?? origin.y + TitleBlockLayout.height
        for stroke in notes.picture.strokes { top = Swift.max(top, stroke.bounds.max.y) }
        for text in notes.picture.texts { top = Swift.max(top, text.origin.y + text.height) }
        let baseline = top + SymbolStyle.of(style.standard).notesGap
        picture.texts.append(
            SheetText(
                run: DrawingText.layout(sentence, height: height), original: sentence, origin: Vector2(origin.x, baseline),
                height: height, layer: .text, isNotice: true))
    }

    /// The top of a parts list standing on the title block (the notes stand above it), or `nil` when there isn't one (R7).
    private static func notesBase(for sheet: DrawingSheet, standard: DrawingStandard, rows: Int) -> Double? {
        guard let list = sheet.partsList, list.list.bottomRight == nil else { return nil }
        let origin = TitleBlockLayout.origin(for: sheet, standard: standard)
        return origin.y + TitleBlockLayout.height + PartsListLayout.height(rows: rows)
    }

    private static func appendLabel(
        to picture: inout SheetPicture, view: DrawingView, center: Vector2, frame: Rect2D, sheet: DrawingSheet, style: DrawingStyle
    ) {
        guard view.showsLabel else { return }
        let label = ViewLabel.text(for: view, sheet: sheet, standard: style.standard)
        let height = style.viewLabelHeight
        let run = DrawingText.layout(label, height: height)
        picture.texts.append(
            SheetText(
                run: run, original: label, origin: Vector2(center.x - run.width / 2, frame.min.y - 8 - height / 2),
                height: height, layer: .text, view: view.id))
    }

    /// A view's problem (when its last projection is still drawn) and its warnings, under the frame and its label, in the
    /// warning colour. On screen only: `notices` is false for a file.
    private static func appendNotices(
        to picture: inout SheetPicture, placed: Placed, frame: Rect2D, sheet: DrawingSheet, style: DrawingStyle,
        contents: [ViewID: ViewContent]
    ) {
        let (view, center, content) = (placed.view, placed.center, placed.content)
        var lines = DerivedViewNotices.notices(for: view, in: sheet, contents: contents) + content.warnings
        if content.projection != nil, let problem = content.problem, !problem.isEmpty { lines.insert(problem, at: 0) }
        guard !lines.isEmpty else { return }
        let height = style.notesHeight(for: sheet.size)
        var top = frame.min.y - 2
        if view.showsLabel { top -= 6 + style.viewLabelHeight }
        for (index, line) in lines.enumerated() {
            let run = DrawingText.layout(line, height: height)
            let baseline = top - Double(index + 1) * (height + 1)
            picture.texts.append(
                SheetText(
                    run: run, original: line, origin: Vector2(center.x - run.width / 2, baseline), height: height,
                    layer: .text, view: view.id, isNotice: true))
        }
    }

    /// A view with no projection: its frame (grown to hold the problem text) and the problem centred in it.
    private static func appendEmptyView(
        to picture: inout SheetPicture, placed: Placed, sheet: DrawingSheet, style: DrawingStyle, notices: Bool
    ) -> Rect2D {
        let (view, center, content) = (placed.view, placed.center, placed.content)
        var size = content.lastSize ?? defaultEmptySize
        let height = style.notesHeight(for: sheet.size)
        var layout: (text: String, run: TextRun)?
        if let problem = content.problem, !problem.isEmpty {
            let run = DrawingText.layout(problem, height: height)
            layout = (problem, run)
            size = Vector2(max(size.x, run.width + 2 * problemMargin), max(size.y, height + 2 * problemMargin))
        }
        let frame = Rect2D(
            min: center - Vector2(size.x / 2, size.y / 2), max: center + Vector2(size.x / 2, size.y / 2))
        // The placeholder box is on screen only: a file leaves it out and says the view has nothing drawn (drawings minors R2).
        if notices {
            picture.strokes.append(
                SheetStroke(
                    segments: [.polyline(SheetFrame.closedPoints(of: frame))], width: style.thin, layer: .frame, view: view.id))
        }
        var label = ViewLabel.text(for: view, sheet: sheet, standard: style.standard)
        if label.hasSuffix(")"), let open = label.range(of: " (", options: .backwards) { label = String(label[..<open.lowerBound]) }
        picture.emptyViews.append(EmptyViewNote(id: view.id, sentence: "The view \u{201C}\(label)\u{201D} has nothing drawn."))
        if notices, let (problem, run) = layout {
            picture.texts.append(
                SheetText(
                    run: run, original: problem,
                    origin: Vector2(center.x - run.width / 2, center.y - height / 2), height: height,
                    layer: .text, view: view.id, isNotice: true))
        }
        return frame
    }
}
