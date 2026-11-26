import CreatorGeometry
import CreatorKernel
import Foundation

/// What an annotation adds to the picture: strokes, fills and texts, tagged with the view and the annotation.
struct AnnotationPieces {
    var strokes: [SheetStroke] = []
    var fills: [SheetFill] = []
    var texts: [SheetText] = []
    var frame: Rect2D?

    mutating func append(_ other: AnnotationPieces) {
        strokes += other.strokes
        fills += other.fills
        texts += other.texts
        if let more = other.frame { frame = frame.map { $0.union(more) } ?? more }
    }
}

/// What a view lets its annotations do (plan R25).
enum AnnotationViewState {
    /// Resolve and measure against this topology.
    case annotated(Topology, ProjectionFrame)
    /// A projection is still drawn but its annotations are lost: drawn from their last values (a failed view, no topology).
    case failed(LostReason)
    /// No projection: the annotations are listed and not drawn.
    case unlisted(LostReason)

    /// The reason a view with this content (or none) is in this state, from its problem sentence.
    static func reason(for problem: String?) -> LostReason {
        guard let problem, !problem.isEmpty else { return .noPart }
        switch problem {
        case DrawingProjector.removedSentence: return .sourceRemoved
        case DrawingProjector.nothingYetSentence, DrawingProjector.onlyMeshesSentence: return .noPart
        default: return .viewFailed(problem)
        }
    }

    static func of(_ content: ViewContent, frame: ProjectionFrame) -> AnnotationViewState {
        guard content.projection != nil else { return .unlisted(reason(for: content.problem)) }
        if let problem = content.problem, !problem.isEmpty { return .failed(reason(for: problem)) }
        guard let topology = content.topology else { return .failed(.noPart) }
        return .annotated(topology, frame)
    }
}

/// Where and how a view's annotations are composed.
struct AnnotationContext {
    /// `nil` for a note free on the sheet.
    var view: ViewID?
    /// The view's resolved centre, which a view note's position is relative to; zero for a free note.
    var center: Vector2
    /// `nil` when the view has no projection.
    var mapping: ViewMapping?
    var viewFrame: Rect2D
    var projection: Projection2D?
    var state: AnnotationViewState
    var standard: DrawingStandard
    var style: AnnotationStyle
    var drawingStyle: DrawingStyle
    var height: Double
}

/// Composes one annotation: resolve, measure, label, lay out and tag (plan R15, R25).
enum AnnotationComposer {
    static func compose(
        _ annotation: DrawingAnnotation, context: AnnotationContext, format: NumberFormat, remembered: LastGood?
    ) -> (report: AnnotationReport, pieces: AnnotationPieces) {
        if case .note(let note) = annotation.kind {
            return composeNote(annotation, note, context: context, remembered: remembered ?? annotation.last)
        }
        switch context.state {
        case .unlisted(let reason):
            let last = remembered ?? annotation.last
            let label = lostLabel(annotation, last: last)
            return (
                AnnotationReport(status: .lost(reason), label: reportText(annotation, label) ?? "?"), AnnotationPieces())
        case .failed(let reason):
            return lostDrawn(annotation, reason: reason, anchors: [], context: context, last: remembered ?? annotation.last)
        case .annotated(let topology, let frame):
            guard let evaluated = AnnotationEvaluator.evaluate(annotation, topology: topology, frame: frame, format: format) else {
                return (AnnotationReport(status: .lost(.noPart)), AnnotationPieces())
            }
            switch evaluated.outcome {
            case .failure(let reason):
                return lostDrawn(
                    annotation, reason: reason, anchors: evaluated.anchors, context: context, last: remembered ?? annotation.last)
            case .success(let held):
                let made = pieces(of: annotation, figure: held.current.figure, labels: held.labels, context: context, isLost: false)
                let report = AnnotationReport(
                    status: .held, anchors: evaluated.anchors, current: held.current, label: held.label,
                    frame: made.value.frame ?? Rect2D(min: .zero, max: .zero), textCenter: made.drawing?.textCenter)
                return (report, made.value)
            }
        }
    }

    // MARK: Lost

    /// A lost annotation: its last figure through the view's mapping, every value marked "?"; a lone "?" with nothing remembered.
    private static func lostDrawn(
        _ annotation: DrawingAnnotation, reason: LostReason, anchors: [AnchorStatus], context: AnnotationContext, last: LastGood?
    ) -> (report: AnnotationReport, pieces: AnnotationPieces) {
        let labels = lostLabel(annotation, last: last)
        var drawn: (value: AnnotationPieces, drawing: AnnotationDrawing?)?
        if let last, context.mapping != nil {
            let made = pieces(of: annotation, figure: last.figure, labels: labels, context: context, isLost: true)
            if made.value.frame != nil { drawn = made }
        }
        let text = reportText(annotation, labels)?.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init)
        var report = AnnotationReport(status: .lost(reason), anchors: anchors, label: text ?? "?")
        if let drawn {
            report.frame = drawn.value.frame ?? report.frame
            report.textCenter = drawn.drawing?.textCenter
            return (report, drawn.value)
        }
        // Nothing to draw from: a lone "?" at the view frame's bottom left (a view with no projection draws nothing).
        guard context.mapping != nil else { return (report, AnnotationPieces()) }
        report.label = "?"
        let run = DrawingText.layout("?", height: context.height)
        let origin = context.viewFrame.min
        let mark = SheetText(
            run: run, original: "?", origin: origin, height: context.height, layer: .dimension, view: context.view,
            annotation: annotation.id, isLost: true)
        var out = AnnotationPieces()
        out.texts = [mark]
        out.frame = Rect2D(min: origin, max: origin + Vector2(run.width, context.height))
        report.frame = out.frame ?? report.frame
        return (report, out)
    }

    /// The text a lost annotation's report names: the label `shownLabel` picks, so an ordinate's origin "0" is skipped.
    private static func reportText(_ annotation: DrawingAnnotation, _ labels: [DimensionLabel]) -> String? {
        if case .dimension(let dimension) = annotation.kind { return AnnotationEvaluator.shownLabel(of: dimension, labels)?.plainText }
        return labels.first?.plainText
    }

    /// The labels of a lost annotation: its remembered lines, the first of each marked "?".
    private static func lostLabel(_ annotation: DrawingAnnotation, last: LastGood?) -> [DimensionLabel] {
        guard let last, !last.lines.isEmpty else { return [] }
        switch annotation.kind {
        case .holeCallout: return [DimensionLabel.restored(from: last.lines).lost()]
        case .dimension(let dimension):
            var isOrdinate = false
            if case .ordinate = dimension.kind { isOrdinate = true }
            return last.lines.enumerated().map { index, line in
                let label = DimensionLabel.restored(from: [line])
                return isOrdinate && index == 0 ? label : label.lost()
            }
        default: return []
        }
    }

    // MARK: Drawing

    /// The pieces of `figure` as the annotation's kind draws them, with the layout's drawing when it has one.
    private static func pieces(
        of annotation: DrawingAnnotation, figure: AnnotationFigure, labels: [DimensionLabel], context: AnnotationContext,
        isLost: Bool
    ) -> (value: AnnotationPieces, drawing: AnnotationDrawing?) {
        guard let mapping = context.mapping else { return (AnnotationPieces(), nil) }
        switch (annotation.kind, figure) {
        case (.dimension(let dimension), _):
            guard !labels.isEmpty else { return (AnnotationPieces(), nil) }
            let drawing = SheetDimensionLayout.draw(
                figure, kind: dimension.kind, labels: labels, placement: dimension.placement, mapping: mapping,
                standard: context.standard, height: context.height)
            return (tagged(drawing, annotation: annotation.id, context: context, isLost: isLost), drawing)
        case (.holeCallout(let callout), .hole(let center, let radius)):
            guard let label = labels.first else { return (AnnotationPieces(), nil) }
            let drawing = SheetDimensionLayout.callout(
                center: center, radius: radius, lines: label, placement: callout.placement, mapping: mapping,
                standard: context.standard, height: context.height)
            return (tagged(drawing, annotation: annotation.id, context: context, isLost: isLost), drawing)
        case (.centreMark, .centreMark(let center, let radius)):
            let strokes = CentreMarkComposer.mark(
                center: center, radius: radius, mapping: mapping, tag: tag(annotation, context, isLost), styles: styles(context))
            return (stroked(strokes), nil)
        case (.centreLine, .centreLine(let start, let end)):
            let strokes = CentreMarkComposer.line(
                start: start, end: end, mapping: mapping, tag: tag(annotation, context, isLost), styles: styles(context))
            return (stroked(strokes), nil)
        default: return (AnnotationPieces(), nil)
        }
    }

    private static func tag(_ annotation: DrawingAnnotation, _ context: AnnotationContext, _ isLost: Bool) -> CentreMarkComposer.Tag {
        CentreMarkComposer.Tag(view: context.view, annotation: annotation.id, isLost: isLost)
    }

    private static func styles(_ context: AnnotationContext) -> CentreMarkComposer.Styles {
        CentreMarkComposer.Styles(annotation: context.style, drawing: context.drawingStyle)
    }

    private static func stroked(_ strokes: [SheetStroke]) -> AnnotationPieces {
        var out = AnnotationPieces()
        out.strokes = strokes
        out.frame = bounds(of: strokes)
        return out
    }

    static func bounds(of strokes: [SheetStroke]) -> Rect2D? {
        guard let first = strokes.first?.bounds else { return nil }
        return strokes.dropFirst().reduce(first) { $0.union($1.bounds) }
    }

    /// Tags a layout's drawing with the view and the annotation: one thin stroke per segment, so a hit finds the piece.
    static func tagged(
        _ drawing: AnnotationDrawing, annotation: AnnotationID, context: AnnotationContext, isLost: Bool
    ) -> AnnotationPieces {
        var out = AnnotationPieces()
        let thin = context.drawingStyle.thin
        for segment in drawing.segments {
            out.strokes.append(
                SheetStroke(
                    segments: [segment], width: thin, layer: .dimension, view: context.view, annotation: annotation, isLost: isLost))
        }
        for box in drawing.boxes {
            out.strokes.append(
                SheetStroke(
                    segments: [.polyline(box)], width: thin, layer: .dimension, view: context.view, annotation: annotation,
                    isLost: isLost))
        }
        for fill in drawing.fills {
            out.fills.append(SheetFill(points: fill, layer: .dimension, view: context.view, annotation: annotation, isLost: isLost))
        }
        for text in drawing.texts {
            out.texts.append(
                SheetText(
                    run: text.run, original: text.original, origin: text.origin, height: text.height, layer: .dimension,
                    view: context.view, angle: text.angle, annotation: annotation, isLost: isLost))
        }
        out.frame = drawing.frame
        return out
    }
}
