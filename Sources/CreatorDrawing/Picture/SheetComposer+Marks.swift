import CreatorGeometry

extension SheetComposer {
    /// A section's hatch, in its own view, on the page's standard spacing.
    static func hatch(
        for view: DrawingView, content: ViewContent, center: Vector2, scale: Double, sheet: DrawingSheet, style: DrawingStyle
    ) -> [SheetStroke] {
        guard !content.hatch.isEmpty, let mapping = ViewMapping.of(content: content, center: center, scale: scale) else { return [] }
        return HatchPattern.strokes(
            content.hatch, mapping: mapping, clips: content.hatchClips, spacing: style.hatchSpacing(for: sheet.size),
            width: style.thin, view: view.id)
    }

    /// The marks of every derived view, after all views: a section's or auxiliary view's on its parent (only while the parent is
    /// there and looks as it did), a detail's circle on its parent and its boundary on itself. The extents of the view that carries a
    /// mark grow to hold it.
    static func appendMarks(
        to picture: inout SheetPicture, sheet: DrawingSheet, standard: DrawingStandard, centers: [ViewID: Vector2],
        contents: [ViewID: ViewContent]
    ) {
        for view in sheet.views {
            guard let derivation = view.derivation else { continue }
            let letter = view.letter ?? ""
            if case .detail(let circle) = derivation {
                appendBoundary(
                    of: view, circle: circle, to: &picture, standard: standard,
                    placed: (center: centers[view.id] ?? view.center, scale: (view.scale ?? sheet.scale).value),
                    content: contents[view.id])
            }
            guard let parent = sheet.view(derivation.parent), parent.id != view.id,
                let mapping = ViewMapping.of(
                    content: contents[parent.id] ?? ViewContent(), center: centers[parent.id] ?? parent.center,
                    scale: (parent.scale ?? sheet.scale).value)
            else { continue }
            let pieces: SectionMarks.Pieces
            switch derivation {
            case .section(let line):
                guard DerivedViewNotices.marksAreShown(for: view, in: sheet, contents: contents) else { continue }
                pieces = SectionMarks.cuttingLine(
                    line.cutter, letter: letter, mapping: mapping, parent: parent.id, mark: view.id, standard: standard)
            case .auxiliary(let arrow):
                guard DerivedViewNotices.marksAreShown(for: view, in: sheet, contents: contents) else { continue }
                pieces = SectionMarks.auxiliaryArrow(
                    arrow, letter: letter, mapping: mapping, parent: parent.id, mark: view.id, standard: standard)
            case .detail(let circle):
                pieces = SectionMarks.detailCircle(
                    circle, letter: letter, mapping: mapping, parent: parent.id, mark: view.id, standard: standard)
            }
            add(pieces, to: &picture, extending: parent.id)
        }
    }

    private static func appendBoundary(
        of view: DrawingView, circle: DetailCircle, to picture: inout SheetPicture, standard: DrawingStandard,
        placed: (center: Vector2, scale: Double), content: ViewContent?
    ) {
        guard let content, content.framing != nil, content.projection != nil else { return }
        add(
            SectionMarks.detailBoundary(
                center: placed.center, radius: circle.radius * placed.scale, view: view.id, standard: standard),
            to: &picture, extending: view.id)
    }

    private static func add(_ pieces: SectionMarks.Pieces, to picture: inout SheetPicture, extending view: ViewID) {
        picture.strokes += pieces.strokes
        picture.fills += pieces.fills
        picture.texts += pieces.texts
        guard let box = SectionMarks.bounds(of: pieces) else { return }
        let known = picture.viewExtents[view] ?? picture.viewFrames[view]
        picture.viewExtents[view] = known.map { $0.union(box) } ?? box
    }
}
