import CreatorGeometry

/// Builds a sheet's whole picture: frame, title block and each view (plan R7, R11, R18).
public enum SheetComposer {
    static let defaultEmptySize = Vector2(40, 30)
    static let problemMargin = 4.0

    public static func compose(
        _ sheet: DrawingSheet, in document: DrawingDocument, contents: [ViewID: ViewContent], facts: TitleBlockFacts
    ) -> SheetPicture {
        let settings = document.settings
        let standard = settings.standard
        let style = DrawingStyle.of(standard)
        var picture = SheetFrame.picture(for: sheet, standard: standard)
        let index = document.sheets.firstIndex { $0.id == sheet.id } ?? 0
        picture.append(
            TitleBlockLayout.picture(
                sheet: sheet, settings: settings, facts: facts, sheetIndex: index, sheetCount: document.sheets.count))

        let centers = ViewPlacement.centers(in: sheet)
        for view in sheet.views {
            let center = centers[view.id] ?? view.center
            let scale = (view.scale ?? sheet.scale).value
            let content = contents[view.id] ?? ViewContent()
            var frame: Rect2D
            if let projection = content.projection {
                picture.strokes += ViewLinework.strokes(
                    for: projection, view: view, center: center, scale: scale, style: style)
                frame = ViewLinework.frame(for: projection, center: center, scale: scale)
                    ?? Rect2D(min: center, max: center)
            } else {
                frame = appendEmptyView(
                    to: &picture, view: view, center: center, content: content, sheet: sheet, style: style)
            }
            picture.viewFrames[view.id] = frame
            if view.showsLabel {
                let label = ViewLabel.text(for: view, sheet: sheet, standard: standard)
                let height = style.viewLabelHeight
                let run = DrawingText.layout(label, height: height)
                picture.texts.append(
                    SheetText(
                        run: run, original: label,
                        origin: Vector2(center.x - run.width / 2, frame.min.y - 8 - height / 2), height: height,
                        layer: .text, view: view.id))
            }
        }
        return picture
    }

    /// A view with no projection: its frame (grown to hold the problem text) and the problem centred in it.
    private static func appendEmptyView(
        to picture: inout SheetPicture, view: DrawingView, center: Vector2, content: ViewContent,
        sheet: DrawingSheet, style: DrawingStyle
    ) -> Rect2D {
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
        picture.strokes.append(
            SheetStroke(
                segments: [.polyline(SheetFrame.closedPoints(of: frame))], width: style.thin, layer: .frame,
                view: view.id))
        if let (problem, run) = layout {
            picture.texts.append(
                SheetText(
                    run: run, original: problem,
                    origin: Vector2(center.x - run.width / 2, center.y - height / 2), height: height,
                    layer: .text, view: view.id))
        }
        return frame
    }
}
